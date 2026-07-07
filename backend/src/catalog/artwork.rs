//! Read-through access to artwork. Artwork has no translations (only a `language`
//! attribute on the image itself).

use serde_json::Value;

use crate::{
    catalog::{TTL, as_i32, as_i64, models::ArtworkRow},
    error::{AppError, AppResult},
    state::AppState,
};

/// All artworks for a series/movie, best-scored first, read from the normalized
/// `catalog.artwork` table (populated by [`store_for`] on upsert + migration 0037).
pub async fn list_for_entity(state: &AppState, entity_type: &str, entity_id: i64) -> AppResult<Vec<ArtworkRow>> {
    let col = if entity_type == "movie" { "movie_id" } else { "series_id" };
    let rows = sqlx::query_as::<_, ArtworkRow>(&format!(
        "SELECT id, series_id, movie_id, season_id, episode_id, type AS art_type, language, \
                image_url, thumbnail_url, width, height, score \
         FROM catalog.artwork WHERE {col} = $1 AND image_url IS NOT NULL \
         ORDER BY score DESC NULLS LAST, id"
    ))
    .bind(entity_id)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// Upsert every artwork embedded in a series/movie `?extended` record into
/// `catalog.artwork` (one statement). Keeps the normalized table in step with the
/// entity on each refresh; best-effort — callers ignore failures so a bad artwork
/// never fails the parent upsert.
pub async fn store_for(state: &AppState, entity_type: &str, entity_id: i64, data: &Value) -> AppResult<()> {
    let Some(arts) = data["artworks"].as_array() else { return Ok(()) };
    let mut ids: Vec<i64> = Vec::new();
    let mut types: Vec<Option<i32>> = Vec::new();
    let mut langs: Vec<Option<String>> = Vec::new();
    let mut images: Vec<String> = Vec::new();
    let mut thumbs: Vec<Option<String>> = Vec::new();
    let mut widths: Vec<Option<i32>> = Vec::new();
    let mut heights: Vec<Option<i32>> = Vec::new();
    let mut scores: Vec<Option<f64>> = Vec::new();
    for a in arts {
        let (Some(id), Some(image)) = (as_i64(&a["id"]), a["image"].as_str()) else { continue };
        ids.push(id);
        types.push(as_i32(&a["type"]));
        langs.push(a["language"].as_str().filter(|s| !s.is_empty()).map(str::to_string));
        images.push(image.to_string());
        thumbs.push(a["thumbnail"].as_str().map(str::to_string));
        widths.push(as_i32(&a["width"]));
        heights.push(as_i32(&a["height"]));
        scores.push(a["score"].as_f64());
    }
    if ids.is_empty() {
        return Ok(());
    }
    let (series_id, movie_id) =
        if entity_type == "movie" { (None, Some(entity_id)) } else { (Some(entity_id), None) };
    sqlx::query(
        "INSERT INTO catalog.artwork \
           (id, series_id, movie_id, type, language, image_url, thumbnail_url, width, height, score, last_synced_at) \
         SELECT u.id, $2, $3, u.type, u.language, u.image, u.thumb, u.width, u.height, u.score, now() \
         FROM unnest($1::bigint[], $4::int[], $5::text[], $6::text[], $7::text[], $8::int[], $9::int[], \
                     $10::double precision[]) AS u(id, type, language, image, thumb, width, height, score) \
         ON CONFLICT (id) DO UPDATE SET \
           series_id=EXCLUDED.series_id, movie_id=EXCLUDED.movie_id, type=EXCLUDED.type, \
           language=EXCLUDED.language, image_url=EXCLUDED.image_url, thumbnail_url=EXCLUDED.thumbnail_url, \
           width=EXCLUDED.width, height=EXCLUDED.height, score=EXCLUDED.score, last_synced_at=now()",
    )
    .bind(&ids)
    .bind(series_id)
    .bind(movie_id)
    .bind(&types)
    .bind(&langs)
    .bind(&images)
    .bind(&thumbs)
    .bind(&widths)
    .bind(&heights)
    .bind(&scores)
    .execute(&state.db)
    .await?;
    Ok(())
}

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
