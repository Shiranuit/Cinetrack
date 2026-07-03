//! Extract filterable facets (genres, themes/tags, companies, season count) from a
//! series `/extended` payload into the normalized `catalog.*` tables that power
//! advanced filtering. Refreshed on every `series::upsert`.

use serde_json::Value;
use sqlx::PgPool;

use crate::{catalog::as_i64, error::AppResult, state::AppState};

/// Number of official-order, non-special seasons in the payload.
pub fn season_count(data: &Value) -> Option<i32> {
    let seasons = data["seasons"].as_array()?;
    let n = seasons
        .iter()
        .filter(|s| {
            s["type"]["type"].as_str() == Some("official")
                && s["number"].as_i64().is_some_and(|num| num > 0)
        })
        .count();
    Some(n as i32)
}

/// Refresh genre / tag / company links for a series from its `/extended` payload.
pub async fn upsert_series_facets(state: &AppState, series_id: i64, data: &Value) -> AppResult<()> {
    set_genres(&state.db, series_id, data).await?;
    set_tags(&state.db, series_id, data).await?;
    set_companies(&state.db, series_id, data).await?;
    Ok(())
}

/// Re-derive facets (genres/tags/companies + season/episode counts) for every
/// already-mirrored series from its stored `raw` — no TheTVDB calls. Backfills
/// data cached before these tables existed. Returns the number processed.
pub async fn backfill(state: &AppState) -> AppResult<usize> {
    let rows: Vec<(i64, sqlx::types::Json<Value>)> =
        sqlx::query_as("SELECT id, raw FROM catalog.series WHERE raw IS NOT NULL AND NOT deleted")
            .fetch_all(&state.db)
            .await?;
    let n = rows.len();
    for (id, raw) in rows {
        upsert_series_facets(state, id, &raw.0).await?;
        sqlx::query(
            "UPDATE catalog.series SET season_count = $2, \
                episode_count = (SELECT count(*) FROM catalog.episode \
                                 WHERE series_id = $1 AND NOT deleted AND season_number > 0) \
             WHERE id = $1",
        )
        .bind(id)
        .bind(season_count(&raw.0))
        .execute(&state.db)
        .await?;
    }
    Ok(n)
}

async fn set_genres(db: &PgPool, series_id: i64, data: &Value) -> AppResult<()> {
    sqlx::query("DELETE FROM catalog.series_genre WHERE series_id = $1").bind(series_id).execute(db).await?;
    for g in data["genres"].as_array().into_iter().flatten() {
        let (Some(gid), Some(name)) = (as_i64(&g["id"]), g["name"].as_str()) else { continue };
        sqlx::query("INSERT INTO catalog.genre (id, name, slug) VALUES ($1,$2,$3) ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name")
            .bind(gid).bind(name).bind(g["slug"].as_str()).execute(db).await?;
        sqlx::query("INSERT INTO catalog.series_genre (series_id, genre_id) VALUES ($1,$2) ON CONFLICT DO NOTHING")
            .bind(series_id).bind(gid).execute(db).await?;
    }
    Ok(())
}

async fn set_tags(db: &PgPool, series_id: i64, data: &Value) -> AppResult<()> {
    sqlx::query("DELETE FROM catalog.series_tag WHERE series_id = $1").bind(series_id).execute(db).await?;
    for t in data["tags"].as_array().into_iter().flatten() {
        // `name` is the theme (e.g. "Love Triangle"); `tagName` is its category.
        let (Some(tid), Some(name)) = (as_i64(&t["id"]), t["name"].as_str()) else { continue };
        sqlx::query("INSERT INTO catalog.tag (id, name, category) VALUES ($1,$2,$3) ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, category=EXCLUDED.category")
            .bind(tid).bind(name).bind(t["tagName"].as_str()).execute(db).await?;
        sqlx::query("INSERT INTO catalog.series_tag (series_id, tag_id) VALUES ($1,$2) ON CONFLICT DO NOTHING")
            .bind(series_id).bind(tid).execute(db).await?;
    }
    Ok(())
}

async fn set_companies(db: &PgPool, series_id: i64, data: &Value) -> AppResult<()> {
    sqlx::query("DELETE FROM catalog.series_company WHERE series_id = $1").bind(series_id).execute(db).await?;
    for c in data["companies"].as_array().into_iter().flatten() {
        let (Some(cid), Some(name)) = (as_i64(&c["id"]), c["name"].as_str()) else { continue };
        let kind = c["companyType"]["companyTypeName"].as_str().unwrap_or("Other");
        sqlx::query("INSERT INTO catalog.company (id, name) VALUES ($1,$2) ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name")
            .bind(cid).bind(name).execute(db).await?;
        sqlx::query("INSERT INTO catalog.series_company (series_id, company_id, kind) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING")
            .bind(series_id).bind(cid).bind(kind).execute(db).await?;
    }
    Ok(())
}
