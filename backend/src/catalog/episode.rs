//! Read-through access to episodes.

use serde_json::Value;

use crate::{
    catalog::{TTL, as_i32, as_i64, models::EpisodeRow, translation},
    error::{AppError, AppResult},
    state::AppState,
};

pub async fn get(state: &AppState, id: i64, lang: Option<&str>) -> AppResult<EpisodeRow> {
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT last_synced_at > now() - interval '{TTL}' \
         FROM catalog.episode WHERE id = $1 AND NOT deleted"
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    if fresh != Some(true) {
        if state.config.catalog_mode.allow_remote() {
            let data = state.tvdb.episode(id).await?;
            upsert(state, id, &data).await?;
        } else if fresh.is_none() {
            return Err(AppError::NotFound);
        }
    }

    let mut row = sqlx::query_as::<_, EpisodeRow>(
        "SELECT id, series_id, season_number, number, absolute_number, name, overview, \
                aired::text AS aired, runtime, image_url \
         FROM catalog.episode WHERE id = $1 AND NOT deleted",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    let applied =
        translation::apply(state, "episode", id, lang, &mut row.name, &mut row.overview).await?;
    row.language = applied;
    Ok(row)
}

/// Episodes of a series for a season-type (default `default`), fetched
/// read-through (all pages) and cached, then returned ordered. `lang` requests
/// translated titles inline from TheTVDB (one call per page, no per-episode fetch).
pub async fn list_for_series(
    state: &AppState,
    series_id: i64,
    season_type: &str,
    lang: Option<&str>,
) -> AppResult<Vec<EpisodeRow>> {
    // Make sure the series exists (also caches it / its seasons).
    super::series::get(state, series_id, lang).await?;

    // episodes_synced_at is nullable → COALESCE so a NULL (never synced) decodes as false.
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT COALESCE(episodes_synced_at > now() - interval '{TTL}', false) \
         FROM catalog.series WHERE id = $1"
    ))
    .bind(series_id)
    .fetch_optional(&state.db)
    .await?;

    if fresh != Some(true) && state.config.catalog_mode.allow_remote() {
        let mut page = 0u32;
        loop {
            let data = state.tvdb.series_episodes(series_id, season_type, lang, page).await?;
            let episodes = data["episodes"].as_array().cloned().unwrap_or_default();
            if episodes.is_empty() {
                break;
            }
            for e in &episodes {
                if let Some(id) = as_i64(&e["id"]) {
                    upsert(state, id, e).await?;
                }
            }
            if episodes.len() < 500 {
                break; // last page
            }
            page += 1;
        }
        // Record when we last synced the episode list, and the non-special episode
        // count (for the "# episodes" filter).
        sqlx::query(
            "UPDATE catalog.series SET episodes_synced_at = now(), \
                episode_count = (SELECT count(*) FROM catalog.episode \
                                 WHERE series_id = $1 AND NOT deleted AND season_number > 0) \
             WHERE id = $1",
        )
        .bind(series_id)
        .execute(&state.db)
        .await?;
    }

    let rows = sqlx::query_as::<_, EpisodeRow>(
        "SELECT id, series_id, season_number, number, absolute_number, name, overview, \
                aired::text AS aired, runtime, image_url \
         FROM catalog.episode WHERE series_id = $1 AND NOT deleted \
         ORDER BY season_number NULLS LAST, number NULLS LAST",
    )
    .bind(series_id)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// Force a re-fetch from TheTVDB and upsert (used by the /updates sync worker).
pub async fn refresh(state: &AppState, id: i64) -> AppResult<()> {
    let data = state.tvdb.episode(id).await?;
    upsert(state, id, &data).await
}

pub(crate) async fn upsert(state: &AppState, id: i64, data: &Value) -> AppResult<()> {
    let series_id = as_i64(&data["seriesId"]);
    let season_number = as_i32(&data["seasonNumber"]);
    let number = as_i32(&data["number"]);
    let absolute_number = as_i32(&data["absoluteNumber"]);
    let name = data["name"].as_str();
    let overview = data["overview"].as_str();
    // aired is "YYYY-MM-DD" or empty; cast to date in SQL, NULL when empty.
    let aired = data["aired"].as_str().filter(|s| !s.is_empty());
    let runtime = as_i32(&data["runtime"]);
    let image_url = super::image_url(&data["image"]);
    let is_movie = data["isMovie"].as_i64().map(|n| n != 0);
    let finale_type = data["finaleType"].as_str();
    let last_updated = data["lastUpdated"].as_str();

    sqlx::query(
        "INSERT INTO catalog.episode \
           (id, series_id, season_number, number, absolute_number, name, overview, aired, \
            runtime, image_url, is_movie, finale_type, raw, last_updated, last_synced_at, deleted) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8::date,$9,$10,$11,$12,$13, ($14::timestamp AT TIME ZONE 'UTC'), now(), false) \
         ON CONFLICT (id) DO UPDATE SET \
           series_id=EXCLUDED.series_id, season_number=EXCLUDED.season_number, number=EXCLUDED.number, \
           absolute_number=EXCLUDED.absolute_number, name=EXCLUDED.name, overview=EXCLUDED.overview, \
           aired=EXCLUDED.aired, runtime=EXCLUDED.runtime, image_url=EXCLUDED.image_url, \
           is_movie=EXCLUDED.is_movie, finale_type=EXCLUDED.finale_type, raw=EXCLUDED.raw, \
           last_updated=EXCLUDED.last_updated, last_synced_at=now(), deleted=false",
    )
    .bind(id)
    .bind(series_id)
    .bind(season_number)
    .bind(number)
    .bind(absolute_number)
    .bind(name)
    .bind(overview)
    .bind(aired)
    .bind(runtime)
    .bind(image_url)
    .bind(is_movie)
    .bind(finale_type)
    .bind(sqlx::types::Json(data))
    .bind(last_updated)
    .execute(&state.db)
    .await?;

    Ok(())
}
