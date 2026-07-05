use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde_json::{Value, json};

use crate::{
    catalog::{self, models::{EpisodeRow, SeasonRow}, models::SeriesRow},
    error::AppResult,
    state::AppState,
    web::query::LangQuery,
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
    let lang = LangQuery { lang: q.lang }.resolve();
    Ok(Json(catalog::episode::list_for_series(&state, id, season_type, lang.as_deref()).await?))
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

#[derive(serde::Deserialize)]
pub struct EpisodesQuery {
    pub season_type: Option<String>,
    pub lang: Option<String>,
}
