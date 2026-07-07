use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde_json::{Value, json};

use crate::{
    catalog::{self, models::{EpisodeRow, SeasonRow}, models::SeriesRow},
    error::AppResult,
    state::AppState,
    web::query::{LangQuery, LangsQuery},
};

/// Read-through series. `?lang=eng` (default), `?lang=fra|jpn|...`, `?lang=original`.
pub async fn get_series(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    Query(q): Query<LangQuery>,
) -> AppResult<Json<SeriesRow>> {
    Ok(Json(catalog::series::get(&state, id, q.resolve().as_deref()).await?))
}

/// Languages TheTVDB has translations for (ensures the series is cached first).
pub async fn list_translations(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<Value>> {
    catalog::series::get(&state, id, None).await?;
    let langs = catalog::translation::available_languages(&state, "series", id).await?;
    Ok(Json(json!({ "languages": langs })))
}

/// Episodes of a series (read-through, all pages). `?season_type=default`, `?lang=eng`.
pub async fn list_episodes(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    Query(q): Query<EpisodesQuery>,
) -> AppResult<Json<Vec<EpisodeRow>>> {
    let season_type = q.season_type.as_deref().unwrap_or("default");
    // Prefer the ordered `langs` list; fall back to legacy single `lang` (older app
    // builds) so episode names resolve through the same preference chain as titles.
    let langs = LangsQuery { langs: q.langs.or(q.lang) }.list();
    Ok(Json(catalog::episode::list_for_series(&state, id, season_type, &langs).await?))
}

/// Rich metadata (genres/networks/studios/themes + facts) for the show page.
pub async fn series_details(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<catalog::series::SeriesDetails>> {
    Ok(Json(catalog::series::details(&state, id).await?))
}

/// Seasons of a series (from the mirrored series record).
pub async fn list_seasons(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<Vec<SeasonRow>>> {
    Ok(Json(catalog::season::list_for_series(&state, id).await?))
}

/// All artworks (posters, backgrounds, banners, ...) for a show, best-scored first.
pub async fn list_artworks(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<Vec<catalog::models::ArtworkRow>>> {
    // Ensure the show is cached (in read-through modes this also populates its
    // artworks via the upsert); then read the normalized rows.
    catalog::series::get(&state, id, None).await?;
    Ok(Json(catalog::artwork::list_for_entity(&state, "series", id).await?))
}

#[derive(serde::Deserialize)]
pub struct EpisodesQuery {
    pub season_type: Option<String>,
    /// Legacy single language (older app builds).
    pub lang: Option<String>,
    /// Ordered language preference list (comma-separated); takes precedence.
    pub langs: Option<String>,
}
