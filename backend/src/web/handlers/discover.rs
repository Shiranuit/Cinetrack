use uuid::Uuid;
use axum::{
    Json,
    extract::{Query, State},
};
use serde::{Deserialize, Serialize};

use crate::{
    auth::AuthUser,
    catalog::{
        self, SearchResult,
        discover::{Company, Filters, Genre, Tag},
    },
    error::AppResult,
    state::AppState,
    tracking,
    web::query::{CalendarQuery, LangsQuery, csv_ids, csv_strings},
};

#[derive(Deserialize)]
pub struct DiscoverQuery {
    /// Optional name query: substring match on the title (base + aliases). Lets
    /// Discover and the Library search by name AND filter at the same time.
    pub q: Option<String>,
    /// "series" (default), "movie", or "anime".
    #[serde(rename = "type")]
    pub kind: Option<String>,
    /// "popularity" (default), "year", "name", "runtime", "seasons", "episodes".
    pub sort: Option<String>,
    /// Sort direction: "desc" (default) or "asc".
    pub dir: Option<String>,
    /// Discover only: include shows already in the user's library (default true;
    /// they come back flagged `in_library`). Set false to see only untracked shows.
    pub include_library: Option<bool>,
    pub genres: Option<String>,         // comma ids, must have ALL
    pub exclude_genres: Option<String>, // comma ids, must have NONE
    pub tags: Option<String>,
    pub exclude_tags: Option<String>,
    pub networks: Option<String>, // comma company ids, any-of
    pub studios: Option<String>,
    pub statuses: Option<String>, // comma status names, any-of
    pub year_min: Option<i32>,
    pub year_max: Option<i32>,
    pub runtime_min: Option<i32>,
    pub runtime_max: Option<i32>,
    pub seasons_min: Option<i32>,
    pub seasons_max: Option<i32>,
    pub episodes_min: Option<i32>,
    pub episodes_max: Option<i32>,
    pub score_min: Option<f64>,
    pub favorites: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    pub orig_langs: Option<String>,     // comma codes, any-of (e.g. jpn,eng)
    pub orig_countries: Option<String>, // comma codes, any-of (e.g. jpn,usa)
    pub langs: Option<String>,
    /// Library-only: comma list of Library buckets to keep (any-of), e.g.
    /// `state=watching,stale`. Values come from `tracking::state::STATES`.
    pub state: Option<String>,
    // Library-only watch-history facets. Three distinct clocks, deliberately named
    // apart: when YOU watched it, when its latest episode AIRED, and (via `sort=updated`)
    // when the catalog record changed.
    pub watched_days_min: Option<i32>,
    pub watched_days_max: Option<i32>,
    pub aired_days_min: Option<i32>,
    pub aired_days_max: Option<i32>,
    pub remaining_min: Option<i32>,
    pub remaining_max: Option<i32>,
    pub progress_min: Option<f64>,
    pub progress_max: Option<f64>,
    pub caught_up: Option<bool>,
    pub has_upcoming: Option<bool>,
}

/// Turn a parsed query (or a saved section's stored filter map, which the batch
/// endpoint deserializes into the same type) into the query layer's [`Filters`].
pub fn build_filters(
    q: &DiscoverQuery,
    library_user: Option<Uuid>,
    exclude_user: Option<Uuid>,
    viewer: Option<Uuid>,
    keep_upcoming_in_to_watch: bool,
) -> Filters {
    Filters {
        // Trimmed; ignored if under 2 chars (a 1-char substring is meaningless and
        // can't use the trigram index on the whole-catalog Discover query).
        query: q
            .q
            .as_deref()
            .map(str::trim)
            .filter(|s| s.chars().count() >= 2)
            .map(str::to_string),
        kind: q.kind.clone().unwrap_or_else(|| "series".to_string()),
        genres_include: csv_ids(q.genres.as_deref()),
        genres_exclude: csv_ids(q.exclude_genres.as_deref()),
        tags_include: csv_ids(q.tags.as_deref()),
        tags_exclude: csv_ids(q.exclude_tags.as_deref()),
        networks: csv_ids(q.networks.as_deref()),
        studios: csv_ids(q.studios.as_deref()),
        statuses: csv_strings(q.statuses.as_deref()),
        year_min: q.year_min,
        year_max: q.year_max,
        runtime_min: q.runtime_min,
        runtime_max: q.runtime_max,
        seasons_min: q.seasons_min,
        seasons_max: q.seasons_max,
        episodes_min: q.episodes_min,
        episodes_max: q.episodes_max,
        // Same guard as `progress_*`: NaN makes every comparison false, so the rail
        // renders permanently empty with nothing to explain why.
        score_min: q.score_min.filter(|v| !v.is_nan()),
        original_languages: csv_strings(q.orig_langs.as_deref()),
        original_countries: csv_strings(q.orig_countries.as_deref()),
        // Passed through as-is: absent means "nobody picked a sort", which the
        // query layer resolves per scope. Defaulting here would erase that.
        sort: q.sort.clone(),
        sort_desc: q.dir.as_deref() != Some("asc"),
        limit: q.limit.unwrap_or(120),
        offset: q.offset.unwrap_or(0).max(0),
        library_user,
        exclude_user,
        viewer,
        favorites_only: q.favorites.unwrap_or(false),
        // Unknown bucket names are passed through, NOT dropped. `= ANY(...)` simply
        // never matches them, so a section pinned to a bucket this build doesn't
        // know returns nothing — whereas filtering them out left an empty list,
        // which disables the predicate entirely and silently widens the rail to the
        // user's WHOLE library. A filter that can't be understood must fail closed.
        states: q
            .state
            .as_deref()
            .map(|s| s.split(',').map(str::trim).filter(|v| !v.is_empty()).map(str::to_string).collect())
            .unwrap_or_default(),
        // Clamped, not rejected: these reach the query as date/interval arithmetic,
        // where an out-of-range day count is a Postgres error — `now() - make_interval
        // (days => 2147483647)` is "timestamp out of range", which surfaces as a 500
        // and, from a saved section, on every Library load. Save-time validation
        // stops new ones; clamping keeps anything already stored merely wrong rather
        // than fatal. A negative count would silently mean "in the future".
        watched_days_min: q.watched_days_min.map(clamp_days),
        watched_days_max: q.watched_days_max.map(clamp_days),
        aired_days_min: q.aired_days_min.map(clamp_days),
        aired_days_max: q.aired_days_max.map(clamp_days),
        remaining_min: q.remaining_min.map(|n| n.clamp(0, MAX_EPISODES)),
        remaining_max: q.remaining_max.map(|n| n.clamp(0, MAX_EPISODES)),
        // NaN survives `clamp` and makes every comparison false — an empty rail with
        // no explanation — so it's dropped outright.
        progress_min: q.progress_min.filter(|p| !p.is_nan()).map(|p| p.clamp(0.0, 100.0)),
        progress_max: q.progress_max.filter(|p| !p.is_nan()).map(|p| p.clamp(0.0, 100.0)),
        caught_up: q.caught_up,
        has_upcoming: q.has_upcoming,
        keep_upcoming_in_to_watch,
    }
}

/// Advanced discover over the whole mirrored catalog, excluding shows the user
/// already tracks (discovery = new shows; filter your own shows in the Library).
pub async fn discover(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<DiscoverQuery>,
) -> AppResult<Json<Vec<SearchResult>>> {
    let langs = LangsQuery { langs: q.langs.clone() }.list();
    // Default: INCLUDE the user's tracked shows (they're marked `in_library` so the
    // UI can flag them). Pass `include_library=false` to hide tracked shows and see
    // only new ones.
    let exclude = if q.include_library.unwrap_or(true) { None } else { Some(uid) };
    // Discover is catalog-wide, so no library bucket is classified and the
    // preference cannot apply.
    Ok(Json(catalog::discover::search_db(&state, &build_filters(&q, None, exclude, Some(uid), false), &langs).await?))
}

/// Same advanced filter, scoped to the user's own tracked shows.
pub async fn library_filter(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<DiscoverQuery>,
) -> AppResult<Json<Vec<SearchResult>>> {
    let langs = LangsQuery { langs: q.langs.clone() }.list();
    // Loaded, not defaulted: `state=watching` here must select exactly what the
    // "To watch" rail shows, and the rail is built with this same preference.
    let keep = tracking::keep_upcoming_in_to_watch(&state, uid).await?;
    let f = build_filters(&q, Some(uid), None, Some(uid), keep);
    Ok(Json(catalog::discover::search_db(&state, &f, &langs).await?))
}

/// A century, past which a "days ago" filter stops meaning anything and starts
/// risking date overflow in the query.
const MAX_DAYS: i32 = 36_500;

/// Generous upper bound for episode counts (the catalog's longest running series
/// is under 12,000 episodes).
const MAX_EPISODES: i32 = 100_000;

fn clamp_days(days: i32) -> i32 {
    days.clamp(0, MAX_DAYS)
}


/// Advanced filter scoped to ANOTHER user's shows (empty unless their profile is
/// visible to you) — lets you search/sort inside a friend's library.
pub async fn user_filter(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    axum::extract::Path(target): axum::extract::Path<Uuid>,
    Query(q): Query<DiscoverQuery>,
) -> AppResult<Json<Vec<SearchResult>>> {
    if !tracking::profile_visible(&state, me, target).await? {
        return Ok(Json(vec![]));
    }
    let langs = LangsQuery { langs: q.langs.clone() }.list();
    // The TARGET's preference: it's their library being classified, so their
    // categories are what you're browsing — same reasoning as the rating owner.
    let keep = tracking::keep_upcoming_in_to_watch(&state, target).await?;
    let f = build_filters(&q, Some(target), None, Some(me), keep);
    Ok(Json(catalog::discover::search_db(&state, &f, &langs).await?))
}

#[derive(Deserialize)]
pub struct ScopeQuery {
    /// When true, only options present in the user's library are returned.
    pub library: Option<bool>,
}

#[derive(Serialize)]
pub struct FilterOptions {
    pub genres: Vec<Genre>,
    pub tags: Vec<Tag>,
    pub networks: Vec<Company>,
    pub studios: Vec<Company>,
    pub statuses: Vec<String>,
    pub languages: Vec<String>, // original-language codes present, most common first
    pub countries: Vec<String>, // origin-country codes present, most common first
}

/// The set of filter values that actually exist in the catalog (or the user's
/// library when `?library=true`), so the UI only offers options that return hits.
pub async fn filter_options(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Query(s): Query<ScopeQuery>,
) -> AppResult<Json<FilterOptions>> {
    let lib = if s.library.unwrap_or(false) { Some(uid) } else { None };
    // The seven facet queries are independent catalog-wide aggregations. Run them
    // concurrently (each takes its own pooled connection) so total latency is the
    // slowest one, not their sum — turns ~900ms cold into ~one-query cold.
    let (genres, tags, networks, studios, statuses, languages, countries) = tokio::try_join!(
        catalog::discover::genres_in_catalog(&state, lib),
        catalog::discover::tags_in_catalog(&state, lib),
        catalog::discover::companies_in_catalog(&state, "Network", lib),
        catalog::discover::companies_in_catalog(&state, "Studio", lib),
        catalog::discover::statuses_in_catalog(&state),
        catalog::discover::languages_in_catalog(&state, lib),
        catalog::discover::countries_in_catalog(&state, lib),
    )?;
    Ok(Json(FilterOptions { genres, tags, networks, studios, statuses, languages, countries }))
}

/// Genres present in the mirror (kept for the existing discover chips).
pub async fn genres(AuthUser(_): AuthUser, State(state): State<AppState>) -> AppResult<Json<Vec<Genre>>> {
    Ok(Json(catalog::discover::genres_in_catalog(&state, None).await?))
}

/// Upcoming + recently-aired episodes for followed shows.
pub async fn calendar(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<CalendarQuery>,
) -> AppResult<Json<tracking::Calendar>> {
    Ok(Json(tracking::calendar(&state, me, &q.langs(), q.recent_days).await?))
}
