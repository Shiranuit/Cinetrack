//! Read-through access to seasons.

use serde_json::Value;

use crate::{
    catalog::{TTL, as_i32, as_i64, models::SeasonRow, translation},
    error::{AppError, AppResult},
    state::AppState,
};

pub async fn get(state: &AppState, id: i64, lang: Option<&str>) -> AppResult<SeasonRow> {
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT last_synced_at > now() - interval '{TTL}' \
         FROM catalog.season WHERE id = $1 AND NOT deleted"
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    if fresh != Some(true) {
        if state.config.catalog_mode.allow_remote() {
            let data = state.tvdb.season_extended(id).await?;
            upsert(state, id, &data).await?;
        } else if fresh.is_none() {
            return Err(AppError::NotFound);
        }
    }

    let mut row = sqlx::query_as::<_, SeasonRow>(
        "SELECT id, series_id, number, type AS season_type, name, image_url, year \
         FROM catalog.season WHERE id = $1 AND NOT deleted",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    // Seasons often have no own name; translations still apply where present.
    let mut overview = None;
    let applied =
        translation::apply(state, "season", id, lang, &mut row.name, &mut overview).await?;
    row.language = applied;
    Ok(row)
}

/// Upsert a season embedded in a series' `/extended` `seasons[]` array, where the
/// parent series id is known explicitly (the nested object may omit `seriesId`).
pub(crate) async fn upsert_from_series(state: &AppState, series_id: i64, data: &Value) -> AppResult<()> {
    let Some(id) = as_i64(&data["id"]) else { return Ok(()) };
    let number = as_i32(&data["number"]);
    let season_type = data["type"]["type"].as_str().or_else(|| data["type"]["name"].as_str());
    let name = data["name"].as_str();
    let image_url = data["image"].as_str();
    let year = as_i32(&data["year"]);
    let last_updated = data["lastUpdated"].as_str();

    sqlx::query(
        "INSERT INTO catalog.season \
           (id, series_id, number, type, name, image_url, year, raw, last_updated, last_synced_at, deleted) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8, ($9::timestamp AT TIME ZONE 'UTC'), now(), false) \
         ON CONFLICT (id) DO UPDATE SET \
           series_id=EXCLUDED.series_id, number=EXCLUDED.number, type=EXCLUDED.type, \
           name=COALESCE(EXCLUDED.name, catalog.season.name), \
           image_url=COALESCE(EXCLUDED.image_url, catalog.season.image_url), \
           year=COALESCE(EXCLUDED.year, catalog.season.year), \
           raw=EXCLUDED.raw, last_updated=EXCLUDED.last_updated, last_synced_at=now(), deleted=false",
    )
    .bind(id)
    .bind(series_id)
    .bind(number)
    .bind(season_type)
    .bind(name)
    .bind(image_url)
    .bind(year)
    .bind(sqlx::types::Json(data))
    .bind(last_updated)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Seasons of a series, from the mirrored `catalog.season` rows (populated when
/// the series is fetched). Ensures the series is cached first.
pub async fn list_for_series(state: &AppState, series_id: i64) -> AppResult<Vec<SeasonRow>> {
    super::series::get(state, series_id, None).await?;
    let rows = sqlx::query_as::<_, SeasonRow>(
        "SELECT id, series_id, number, type AS season_type, name, image_url, year \
         FROM catalog.season WHERE series_id = $1 AND NOT deleted \
         ORDER BY number NULLS LAST",
    )
    .bind(series_id)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// Force a re-fetch from TheTVDB and upsert (used by the /updates sync worker).
pub async fn refresh(state: &AppState, id: i64) -> AppResult<()> {
    let data = state.tvdb.season_extended(id).await?;
    upsert(state, id, &data).await
}

async fn upsert(state: &AppState, id: i64, data: &Value) -> AppResult<()> {
    let series_id = as_i64(&data["seriesId"]);
    let number = as_i32(&data["number"]);
    // `type` is a SeasonType object: { id, name, type }.
    let season_type = data["type"]["type"].as_str().or_else(|| data["type"]["name"].as_str());
    let name = data["name"].as_str();
    let image_url = data["image"].as_str();
    let year = as_i32(&data["year"]);
    let last_updated = data["lastUpdated"].as_str();

    sqlx::query(
        "INSERT INTO catalog.season \
           (id, series_id, number, type, name, image_url, year, raw, last_updated, last_synced_at, deleted) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8, ($9::timestamp AT TIME ZONE 'UTC'), now(), false) \
         ON CONFLICT (id) DO UPDATE SET \
           series_id=EXCLUDED.series_id, number=EXCLUDED.number, type=EXCLUDED.type, \
           name=EXCLUDED.name, image_url=EXCLUDED.image_url, year=EXCLUDED.year, \
           raw=EXCLUDED.raw, last_updated=EXCLUDED.last_updated, last_synced_at=now(), deleted=false",
    )
    .bind(id)
    .bind(series_id)
    .bind(number)
    .bind(season_type)
    .bind(name)
    .bind(image_url)
    .bind(year)
    .bind(sqlx::types::Json(data))
    .bind(last_updated)
    .execute(&state.db)
    .await?;

    Ok(())
}
