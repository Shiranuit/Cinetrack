//! Read-through cache over TheTVDB (the local mirror / `catalog.*` domain).
//!
//! On a miss (or stale row) we fetch from TheTVDB, upsert into `catalog.*`, and
//! serve the local copy thereafter. The same tables are later kept fresh by the
//! `/updates` sync worker. Language-specific `name`/`overview` are overlaid from
//! `catalog.translation` (see `translation`).

pub mod alias;
pub mod artwork;
pub mod discover;
pub mod episode;
pub mod facets;
pub mod models;
pub mod movie;
pub mod season;
pub mod series;
pub mod translation;

#[cfg(test)]
mod tests;

use serde_json::Value;

use crate::{error::AppResult, state::AppState};

/// How long a cached catalog row is considered fresh before we re-fetch.
pub(crate) const TTL: &str = "24 hours";

/// A series/movie hit returned by browse/filter (Discover, Library). `name` is
/// resolved to the caller's preferred language when a translation exists.
#[derive(serde::Serialize)]
pub struct SearchResult {
    pub tvdb_id: Option<i64>,
    pub kind: Option<String>, // "series" | "movie"
    pub name: Option<String>,
    pub year: Option<i32>,
    pub image_url: Option<String>,
    pub overview: Option<String>,
}

/// Insert a minimal, deliberately-stale catalog stub for a series/movie we saw
/// via a remote list/search (which carry only lightweight fields). This makes
/// the title locally searchable/browsable immediately; the read-through `get()`
/// enriches it from `/extended` on first open (the `to_timestamp(0)` sync time
/// marks it stale). `ON CONFLICT DO NOTHING` never clobbers a real cached row.
pub(crate) async fn store_stub(
    state: &AppState,
    table: &str, // "catalog.series" | "catalog.movie"
    id: i64,
    name: Option<&str>,
    image_url: Option<&str>,
    year: Option<i32>,
    original_language: Option<&str>,
    aliases: &[String],
) -> AppResult<()> {
    let inserted = sqlx::query(&format!(
        "INSERT INTO {table} (id, name, image_url, year, original_language, aliases, last_synced_at, deleted) \
         VALUES ($1,$2,$3,$4,$5,$6, to_timestamp(0), false) ON CONFLICT (id) DO NOTHING"
    ))
    .bind(id)
    .bind(name)
    .bind(image_url)
    .bind(year)
    .bind(original_language)
    .bind(aliases)
    .execute(&state.db)
    .await?
    .rows_affected();

    // A freshly-created stub → queue it for enrichment right away (enqueue signals
    // the worker). Existing rows (already cached or already queued) are left alone.
    if inserted > 0 {
        let entity = table.strip_prefix("catalog.").unwrap_or(table);
        crate::sync::queue::enqueue_one(state, entity, id, "stub").await?;
    }
    Ok(())
}

/// Coerce a JSON value that may be a number or a numeric string into `i32`.
/// TheTVDB is inconsistent (e.g. `year` is sometimes a string).
pub(crate) fn as_i32(v: &Value) -> Option<i32> {
    v.as_i64()
        .map(|n| n as i32)
        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
}

/// Coerce a JSON value that may be a number or numeric string into `i64`.
pub(crate) fn as_i64(v: &Value) -> Option<i64> {
    v.as_i64().or_else(|| v.as_str().and_then(|s| s.parse().ok()))
}

/// Distinct alias names from a TheTVDB record's `aliases` field. Handles both
/// shapes: `/extended` records give `[{name, language}, …]` while `/search`
/// results give a flat `["Name", …]`.
pub(crate) fn alias_names(data: &Value) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    if let Some(arr) = data["aliases"].as_array() {
        for a in arr {
            let name = a.as_str().or_else(|| a["name"].as_str());
            if let Some(s) = name.map(str::trim).filter(|s| !s.is_empty())
                && !out.iter().any(|x| x == s)
            {
                out.push(s.to_string());
            }
        }
    }
    out
}

/// Normalize a TheTVDB image field to an absolute URL. Episode stills are often
/// returned as relative paths (`/banners/...`) while posters are absolute.
pub(crate) fn image_url(v: &Value) -> Option<String> {
    v.as_str().filter(|s| !s.is_empty()).map(|s| {
        if let Some(rest) = s.strip_prefix('/') {
            format!("https://artworks.thetvdb.com/{rest}")
        } else {
            s.to_string()
        }
    })
}
