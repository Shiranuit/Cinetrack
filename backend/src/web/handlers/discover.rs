use uuid::Uuid;
use axum::{
    Json,
    extract::{Query, State},
};
use serde::{Deserialize, Serialize};

use crate::{
    auth::AuthUser,
    catalog::{
        self,
        discover::{Company, Filters, Genre, Tag},
        search::SearchResult,
    },
    error::AppResult,
    state::AppState,
    tracking,
    web::query::{LangsQuery, csv_ids, csv_strings},
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
    /// Discover only: when true, also include shows already in the user's library
    /// (default false = show only shows they don't track).
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
}

fn build_filters(q: &DiscoverQuery, library_user: Option<Uuid>, exclude_user: Option<Uuid>, viewer: Option<Uuid>) -> Filters {
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
    // Default: exclude the user's tracked shows (Discover = new shows). The
    // "include_library" toggle lets them browse their library shows here too.
    let exclude = if q.include_library.unwrap_or(false) { None } else { Some(uid) };
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
    Ok(Json(FilterOptions {
        genres: catalog::discover::genres_in_catalog(&state, lib).await?,
        tags: catalog::discover::tags_in_catalog(&state, lib).await?,
        networks: catalog::discover::companies_in_catalog(&state, "Network", lib).await?,
        studios: catalog::discover::companies_in_catalog(&state, "Studio", lib).await?,
        statuses: catalog::discover::statuses_in_catalog(&state).await?,
        languages: catalog::discover::languages_in_catalog(&state, lib).await?,
        countries: catalog::discover::countries_in_catalog(&state, lib).await?,
    }))
}

/// Genres present in the mirror (kept for the existing discover chips).
pub async fn genres(AuthUser(_): AuthUser, State(state): State<AppState>) -> AppResult<Json<Vec<Genre>>> {
    Ok(Json(catalog::discover::genres_in_catalog(&state, None).await?))
}

/// Upcoming + recently-aired episodes for followed shows.
pub async fn calendar(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<LangsQuery>,
) -> AppResult<Json<tracking::Calendar>> {
    Ok(Json(tracking::calendar(&state, me, &q.list()).await?))
}
