//! Seed crawl (full scope only): enumerate the entire TheTVDB catalog via
//! `/series?page=N` and `/movies?page=N`, storing each as a lightweight **stub**
//! (id + basic fields, `last_synced_at` pinned to the epoch). The enrichment
//! worker then fills them via `/extended`. See docs/thetvdb-sync-redesign.md §7.
//!
//! Progress is checkpointed per page in `catalog.crawl_state`, so a crawl is
//! resumable across restarts. Once a type is exhausted it's marked `done`;
//! brand-new entities added upstream afterwards arrive via `/updates` (full scope).

use serde_json::Value;

use crate::{
    catalog::{as_i32, as_i64, image_url},
    error::AppResult,
    state::AppState,
    thetvdb::{Priority, with_priority},
};

#[derive(Debug, Default, serde::Serialize)]
pub struct CrawlSummary {
    pub series_pages: u32,
    pub movie_pages: u32,
    pub stubs_added: u64,
}

/// Crawl both series and movies (resuming from the stored cursor). Idempotent:
/// existing rows are never clobbered (`ON CONFLICT DO NOTHING`). Runs at Low
/// priority so interactive requests stay ahead in the pacer.
pub async fn run(state: &AppState) -> AppResult<CrawlSummary> {
    with_priority(Priority::Low, run_inner(state)).await
}

async fn run_inner(state: &AppState) -> AppResult<CrawlSummary> {
    let mut summary = CrawlSummary::default();
    crawl_entity(state, "series", &mut summary).await?;
    crawl_entity(state, "movie", &mut summary).await?;
    tracing::info!("crawl: {summary:?}");
    Ok(summary)
}

async fn crawl_entity(state: &AppState, entity: &str, summary: &mut CrawlSummary) -> AppResult<()> {
    let (mut page, done) = get_cursor(state, entity).await?;
    if done {
        tracing::info!("crawl: {entity} already complete (page {page}); skipping");
        return Ok(());
    }
    let table = if entity == "series" { "catalog.series" } else { "catalog.movie" };

    loop {
        let data = if entity == "series" {
            state.tvdb.series_page(page).await?
        } else {
            state.tvdb.movies_page(page).await?
        };
        let records = data.as_array().cloned().unwrap_or_default();
        if records.is_empty() {
            set_cursor(state, entity, page, true).await?;
            tracing::info!("crawl: {entity} complete at page {page}");
            break;
        }

        summary.stubs_added += upsert_stubs(state, table, &records).await?;
        page += 1;
        if entity == "series" {
            summary.series_pages += 1;
        } else {
            summary.movie_pages += 1;
        }
        // Checkpoint every page so a crash resumes here, not from scratch.
        set_cursor(state, entity, page, false).await?;
    }
    Ok(())
}

/// Batch-insert a page of basic records as stubs (one query). Aliases are left
/// empty here (rectangular-array limitation) — enrichment fills them from
/// `/extended`; the trigger recomputes `search_text` then.
async fn upsert_stubs(state: &AppState, table: &str, records: &[Value]) -> AppResult<u64> {
    let mut ids = Vec::with_capacity(records.len());
    let mut names = Vec::with_capacity(records.len());
    let mut images = Vec::with_capacity(records.len());
    let mut years = Vec::with_capacity(records.len());
    let mut langs = Vec::with_capacity(records.len());

    for r in records {
        let Some(id) = as_i64(&r["id"]) else { continue };
        ids.push(id);
        names.push(r["name"].as_str().map(str::to_string));
        images.push(image_url(&r["image"]));
        years.push(as_i32(&r["year"]));
        langs.push(r["originalLanguage"].as_str().map(str::to_string));
    }
    if ids.is_empty() {
        return Ok(0);
    }

    let n = sqlx::query(&format!(
        "INSERT INTO {table} (id, name, image_url, year, original_language, last_synced_at, deleted) \
         SELECT i, n, img, yr, ol, to_timestamp(0), false \
         FROM UNNEST($1::bigint[], $2::text[], $3::text[], $4::int[], $5::text[]) AS t(i, n, img, yr, ol) \
         ON CONFLICT (id) DO NOTHING"
    ))
    .bind(&ids)
    .bind(&names)
    .bind(&images)
    .bind(&years)
    .bind(&langs)
    .execute(&state.db)
    .await?
    .rows_affected();
    Ok(n)
}

async fn get_cursor(state: &AppState, entity: &str) -> AppResult<(u32, bool)> {
    let row: Option<(i32, bool)> =
        sqlx::query_as("SELECT next_page, done FROM catalog.crawl_state WHERE entity_type = $1")
            .bind(entity)
            .fetch_optional(&state.db)
            .await?;
    Ok(row.map(|(p, d)| (p.max(0) as u32, d)).unwrap_or((0, false)))
}

async fn set_cursor(state: &AppState, entity: &str, next_page: u32, done: bool) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO catalog.crawl_state (entity_type, next_page, done, updated_at) \
         VALUES ($1, $2, $3, now()) \
         ON CONFLICT (entity_type) DO UPDATE SET next_page = $2, done = $3, updated_at = now()",
    )
    .bind(entity)
    .bind(next_page as i32)
    .bind(done)
    .execute(&state.db)
    .await?;
    Ok(())
}
