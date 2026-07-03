//! Read-through access to movies.

use serde_json::Value;

use crate::{
    catalog::{TTL, as_i32, models::MovieRow, translation},
    error::{AppError, AppResult},
    state::AppState,
};

pub async fn get(state: &AppState, id: i64, lang: Option<&str>) -> AppResult<MovieRow> {
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT last_synced_at > now() - interval '{TTL}' \
         FROM catalog.movie WHERE id = $1 AND NOT deleted"
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    if fresh != Some(true) {
        if state.config.catalog_mode.allow_remote() {
            let data = state.tvdb.movie_extended(id).await?;
            upsert(state, id, &data).await?;
        } else if fresh.is_none() {
            return Err(AppError::NotFound);
        }
    }

    let mut row = sqlx::query_as::<_, MovieRow>(
        "SELECT id, name, slug, overview, status, year, runtime, image_url, original_language, score \
         FROM catalog.movie WHERE id = $1 AND NOT deleted",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    let applied =
        translation::apply(state, "movie", id, lang, &mut row.name, &mut row.overview).await?;
    row.language = applied.or_else(|| row.original_language.clone());
    Ok(row)
}

/// Force a re-fetch from TheTVDB and upsert (used by the /updates sync worker).
pub async fn refresh(state: &AppState, id: i64) -> AppResult<()> {
    let data = state.tvdb.movie_extended(id).await?;
    upsert(state, id, &data).await
}

/// Enrichment refresh: fetch the extended record with all translations bundled
/// and store both (see `series::refresh_full`).
pub async fn refresh_full(state: &AppState, id: i64) -> AppResult<()> {
    let data = state.tvdb.movie_extended_translated(id).await?;
    upsert(state, id, &data).await?;
    super::translation::store_bundle(state, "movie", id, &data).await
}

async fn upsert(state: &AppState, id: i64, data: &Value) -> AppResult<()> {
    let name = data["name"].as_str();
    let slug = data["slug"].as_str();
    let overview = data["overview"].as_str();
    let status = data["status"]["name"].as_str();
    let year = as_i32(&data["year"]);
    let runtime = as_i32(&data["runtime"]);
    let image_url = data["image"].as_str();
    let original_language = data["originalLanguage"].as_str();
    let original_country = data["originalCountry"].as_str().filter(|s| !s.is_empty());
    let score = data["score"].as_f64();
    let aliases = super::alias_names(data);
    // Advisory metadata (see series::upsert); NOT the sync dedup key.
    let last_updated = data["lastUpdated"].as_str();

    sqlx::query(
        "INSERT INTO catalog.movie \
           (id, name, slug, overview, status, year, runtime, image_url, original_language, score, aliases, raw, last_updated, original_country, last_synced_at, deleted) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12, ($13::timestamp AT TIME ZONE 'UTC'), $14, now(), false) \
         ON CONFLICT (id) DO UPDATE SET \
           name=EXCLUDED.name, slug=EXCLUDED.slug, overview=EXCLUDED.overview, \
           status=EXCLUDED.status, year=EXCLUDED.year, runtime=EXCLUDED.runtime, \
           image_url=EXCLUDED.image_url, original_language=EXCLUDED.original_language, \
           score=EXCLUDED.score, aliases=EXCLUDED.aliases, raw=EXCLUDED.raw, \
           last_updated=EXCLUDED.last_updated, original_country=EXCLUDED.original_country, last_synced_at=now(), deleted=false",
    )
    .bind(id)
    .bind(name)
    .bind(slug)
    .bind(overview)
    .bind(status)
    .bind(year)
    .bind(runtime)
    .bind(image_url)
    .bind(original_language)
    .bind(score)
    .bind(&aliases)
    .bind(sqlx::types::Json(data))
    .bind(last_updated)
    .bind(original_country)
    .execute(&state.db)
    .await?;

    Ok(())
}
