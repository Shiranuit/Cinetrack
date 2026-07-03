//! Read-through access to artwork. Artwork has no translations (only a `language`
//! attribute on the image itself).

use serde_json::Value;

use crate::{
    catalog::{TTL, as_i32, as_i64, models::ArtworkRow},
    error::{AppError, AppResult},
    state::AppState,
};

pub async fn get(state: &AppState, id: i64) -> AppResult<ArtworkRow> {
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT last_synced_at > now() - interval '{TTL}' FROM catalog.artwork WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    if fresh != Some(true) {
        if state.config.catalog_mode.allow_remote() {
            let data = state.tvdb.artwork_extended(id).await?;
            upsert(state, id, &data).await?;
        } else if fresh.is_none() {
            return Err(AppError::NotFound);
        }
    }

    sqlx::query_as::<_, ArtworkRow>(
        "SELECT id, series_id, movie_id, season_id, episode_id, type AS art_type, language, \
                image_url, thumbnail_url, width, height, score \
         FROM catalog.artwork WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)
}

async fn upsert(state: &AppState, id: i64, data: &Value) -> AppResult<()> {
    let series_id = as_i64(&data["seriesId"]);
    let movie_id = as_i64(&data["movieId"]);
    let season_id = as_i64(&data["seasonId"]);
    let episode_id = as_i64(&data["episodeId"]);
    let art_type = as_i32(&data["type"]);
    let language = data["language"].as_str();
    let image_url = data["image"].as_str();
    let thumbnail_url = data["thumbnail"].as_str();
    let width = as_i32(&data["width"]);
    let height = as_i32(&data["height"]);
    let score = data["score"].as_f64();

    sqlx::query(
        "INSERT INTO catalog.artwork \
           (id, series_id, movie_id, season_id, episode_id, type, language, image_url, \
            thumbnail_url, width, height, score, raw, last_synced_at) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13, now()) \
         ON CONFLICT (id) DO UPDATE SET \
           series_id=EXCLUDED.series_id, movie_id=EXCLUDED.movie_id, season_id=EXCLUDED.season_id, \
           episode_id=EXCLUDED.episode_id, type=EXCLUDED.type, language=EXCLUDED.language, \
           image_url=EXCLUDED.image_url, thumbnail_url=EXCLUDED.thumbnail_url, width=EXCLUDED.width, \
           height=EXCLUDED.height, score=EXCLUDED.score, raw=EXCLUDED.raw, last_synced_at=now()",
    )
    .bind(id)
    .bind(series_id)
    .bind(movie_id)
    .bind(season_id)
    .bind(episode_id)
    .bind(art_type)
    .bind(language)
    .bind(image_url)
    .bind(thumbnail_url)
    .bind(width)
    .bind(height)
    .bind(score)
    .bind(sqlx::types::Json(data))
    .execute(&state.db)
    .await?;

    Ok(())
}
