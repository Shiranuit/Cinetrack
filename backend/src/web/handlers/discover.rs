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
    /// Drop anime from a `series` query — for a caller that wants series but not
    /// anime, which the single `type` value can't express on its own.
    pub exclude_anime: Option<bool>,
    /// Include watch progress on each row, for callers that draw a progress bar.
    pub with_progress: Option<bool>,
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
pub fn build_filters(q: &DiscoverQuery, library_user: Option<Uuid>, exclude_user: Option<Uuid>, viewer: Option<Uuid>) -> Filters {
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
        score_min: q.score_min,
        original_languages: csv_strings(q.orig_langs.as_deref()),
        original_countries: csv_strings(q.orig_countries.as_deref()),
        sort: q.sort.clone().unwrap_or_else(|| "popularity".to_string()),
        sort_desc: q.dir.as_deref() != Some("asc"),
        limit: q.limit.unwrap_or(120),
        offset: q.offset.unwrap_or(0).max(0),
        library_user,
        exclude_user,
        viewer,
        favorites_only: q.favorites.unwrap_or(false),
        // Unknown bucket names are dropped rather than erroring: a section saved by
        // a newer client stays usable, just without the part we don't understand.
        states: q
            .state
            .as_deref()
            .map(|s| {
                s.split(',')
                    .map(str::trim)
                    .filter(|v| crate::tracking::state::is_valid(v))
                    .map(str::to_string)
                    .collect()
            })
            .unwrap_or_default(),
        exclude_anime: q.exclude_anime.unwrap_or(false),
        with_progress: q.with_progress.unwrap_or(false),
        watched_days_min: q.watched_days_min,
        watched_days_max: q.watched_days_max,
        aired_days_min: q.aired_days_min,
        aired_days_max: q.aired_days_max,
        remaining_min: q.remaining_min,
        remaining_max: q.remaining_max,
        progress_min: q.progress_min,
        progress_max: q.progress_max,
        caught_up: q.caught_up,
        has_upcoming: q.has_upcoming,
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
    Ok(Json(catalog::discover::search_db(&state, &build_filters(&q, None, exclude, Some(uid)), &langs).await?))
}

/// Same advanced filter, scoped to the user's own tracked shows.
pub async fn library_filter(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<DiscoverQuery>,
) -> AppResult<Json<Vec<SearchResult>>> {
    let langs = LangsQuery { langs: q.langs.clone() }.list();
    Ok(Json(catalog::discover::search_db(&state, &build_filters(&q, Some(uid), None, Some(uid)), &langs).await?))
}

/// One entry in a batched library-filter request: an opaque client key and the
/// filter to run, as the query-param map a saved section stores.
#[derive(Deserialize)]
pub struct BatchEntry {
    /// Echoed back verbatim so the client can match results to what it asked for.
    /// Opaque here: a section spanning several kinds sends one entry per kind.
    pub key: String,
    pub filters: std::collections::HashMap<String, String>,
}

#[derive(Deserialize)]
pub struct BatchRequest {
    pub sections: Vec<BatchEntry>,
    pub langs: Option<String>,
    pub limit: Option<i64>,
}

#[derive(Serialize)]
pub struct BatchResult {
    pub key: String,
    pub items: Vec<SearchResult>,
}

/// Ceiling on filters per batch. A section spanning kinds sends one entry PER KIND
/// (at most a series-or-anime query plus a movie one), so this is twice the section
/// cap — sizing it to `MAX_SECTIONS` would reject a full layout of mixed sections.
const MAX_BATCH: usize = crate::tracking::sections::MAX_SECTIONS * 2;

/// Rows one rail may return when the caller doesn't say. The Library's built-in
/// rails show every matching title rather than a page, and custom rails match that;
/// the real bound is the user's library size, so this is just a runaway guard.
const RAIL_LIMIT: i64 = 2000;

/// How many of a batch's filters run at once. They're independent queries, so the
/// wall clock is the slowest rather than the sum; the cap keeps one library load
/// from taking a big slice of the pool that the enrich worker shares.
const BATCH_CONCURRENCY: usize = 8;

/// Run several library filters in ONE request.
///
/// The Library draws a rail per custom section, which as separate requests is a
/// round trip each and a connection each. Batching also sets up the win that
/// matters later: once sections can filter on watch state, every rail needs the
/// same per-user aggregate, and computing it once for the whole batch is the
/// difference between one pass over the watch history and N identical ones.
pub async fn library_filter_batch(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<BatchRequest>,
) -> AppResult<Json<Vec<BatchResult>>> {
    if req.sections.len() > MAX_BATCH {
        return Err(crate::error::AppError::BadRequest(format!("too many filters in one batch (max {MAX_BATCH})")));
    }
    let langs = LangsQuery { langs: req.langs.clone() }.list();

    let mut out: Vec<BatchResult> = Vec::with_capacity(req.sections.len());
    // Chunked rather than all-at-once: `BATCH_CONCURRENCY` in flight, in request
    // order, so the response order matches what was asked for.
    for chunk in req.sections.chunks(BATCH_CONCURRENCY) {
        let mut set = tokio::task::JoinSet::new();
        for (i, entry) in chunk.iter().enumerate() {
            // A stored filter IS a query-param map, so parse it with the same
            // deserializer the GET endpoints use rather than a second parser that
            // could drift from `DiscoverQuery`.
            let mut q: DiscoverQuery = serde_urlencoded::from_str(&encode_params(&entry.filters))
                .map_err(|e| crate::error::AppError::BadRequest(format!("bad filter for '{}': {e}", entry.key)))?;
            // Paging is the caller's, not the saved filter's.
            q.limit = Some(req.limit.unwrap_or(RAIL_LIMIT));
            q.offset = None;
            // Rails draw the same cards the built-in ones do, progress bar included.
            q.with_progress = Some(true);
            let (st, ls, key) = (state.clone(), langs.clone(), entry.key.clone());
            set.spawn(async move {
                let items = catalog::discover::search_db(&st, &build_filters(&q, Some(uid), None, Some(uid)), &ls).await;
                (i, key, items)
            });
        }
        let mut done: Vec<(usize, String, AppResult<Vec<SearchResult>>)> = Vec::with_capacity(chunk.len());
        while let Some(joined) = set.join_next().await {
            done.push(joined.expect("library filter batch task panicked"));
        }
        done.sort_by_key(|(i, _, _)| *i);
        for (_, key, items) in done {
            out.push(BatchResult { key, items: items? });
        }
    }
    Ok(Json(out))
}

/// Percent-encode a filter map back into a query string for [`serde_urlencoded`].
fn encode_params(filters: &std::collections::HashMap<String, String>) -> String {
    serde_urlencoded::to_string(filters.iter().collect::<Vec<_>>()).unwrap_or_default()
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
    Ok(Json(catalog::discover::search_db(&state, &build_filters(&q, Some(target), None, Some(me)), &langs).await?))
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
