//! Incremental catalog sync via TheTVDB's `/updates` feed (see
//! `docs/thetvdb-api.md` §4 and `docs/thetvdb-sync-redesign.md`).
//!
//! Each run pulls the global change feed since our checkpoint and, per record,
//! decides what to do WITHOUT fetching inline:
//! - **delete** → soft-delete locally (+ repoint user data on `mergeToId`);
//! - **create/update** → enqueue the entity for the enrichment worker, but only
//!   if it's new-to-us-and-`MIRROR_SCOPE=full`, a stub, or changed at/after that
//!   row's own `last_synced_at` (the per-show dedup key — a fetch already
//!   captured everything up to that point).
//!
//! Existence/freshness is checked one batch per feed page, not per record.
//! Run once via `cargo run --bin sync`, or periodically by `SYNC_INTERVAL_SECS`.

pub mod crawl;
pub mod enrich;
pub mod queue;

use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::Value;

use crate::{
    catalog::as_i64,
    config::MirrorScope,
    error::AppResult,
    state::AppState,
    thetvdb::{Priority, with_priority},
};

/// Entity types we mirror and therefore sync. Artwork is intentionally excluded
/// (huge feed + served straight from TheTVDB's CDN).
const TYPES: [&str; 4] = ["series", "movies", "episodes", "seasons"];

/// Safety cap on pages per type, so a too-wide window can't run away.
const MAX_PAGES: u32 = 200;

/// First-run reconciliation ceiling (TheTVDB `/updates` retention is undocumented
/// but historically ~30 days).
const BOOTSTRAP_WINDOW: &str = "30 days";

#[derive(Debug, Default, serde::Serialize)]
pub struct SyncSummary {
    pub since: i64,
    pub until: i64,
    pub seen: usize,
    pub enqueued: usize, // entities queued for (re)fetch by the enrichment worker
    pub deleted: usize,
    pub merged: usize,
    pub skipped: usize, // redundant (already fresh) or new-but-not-full-scope
}

fn now_unix() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as i64
}

/// Run one full sync pass: scan the feed and enqueue/apply changes. All TheTVDB
/// calls run at Low priority so interactive requests stay ahead in the pacer.
pub async fn run_once(state: &AppState) -> AppResult<SyncSummary> {
    with_priority(Priority::Low, run_once_inner(state)).await
}

async fn run_once_inner(state: &AppState) -> AppResult<SyncSummary> {
    let started = now_unix();
    let since = match get_last_sync_ts(state).await? {
        Some(ts) => ts,
        None => bootstrap_since(state).await?,
    };
    let mut summary = SyncSummary { since, until: started, ..Default::default() };
    let scope = state.config.mirror_scope;

    // If any type hits the page cap, we processed only up to some timeStamp for it.
    // Don't let the checkpoint jump to `now` (that would silently skip the rest);
    // cap it at the earliest such boundary so the next run resumes from there.
    let mut resume: Option<i64> = None;

    for kind in TYPES {
        let mut page = 0;
        let mut last_ts: Option<i64> = None;
        loop {
            let data = state.tvdb.updates(since, kind, page).await?;
            let records = data.as_array().cloned().unwrap_or_default();
            if records.is_empty() {
                break;
            }
            if let Some(ts) = process_page(state, &records, scope, &mut summary).await? {
                last_ts = Some(ts);
            }
            page += 1;
            if records.len() < 500 {
                break;
            }
            if page >= MAX_PAGES {
                let boundary = last_ts.unwrap_or(since);
                tracing::warn!(
                    "sync: hit page cap for '{kind}' — processed up to ts {boundary}; resuming there next run (run more often to avoid this)"
                );
                resume = Some(resume.map_or(boundary, |r| r.min(boundary)));
                break;
            }
        }
    }

    // Caught up fully → advance to run-start; capped → resume boundary.
    let checkpoint = resume.unwrap_or(started);
    summary.until = checkpoint;
    set_last_sync_ts(state, checkpoint).await?;
    tracing::info!("sync: {summary:?}");
    Ok(summary)
}

/// First-run cursor: the oldest non-stub `last_synced_at` in the mirror, floored
/// at the retention window — so we reconcile everything changed since, without
/// assuming the mirror is fresh. Empty mirror → now (nothing to reconcile yet).
async fn bootstrap_since(state: &AppState) -> AppResult<i64> {
    let ts: i64 = sqlx::query_scalar(&format!(
        "SELECT extract(epoch FROM GREATEST(COALESCE(min(ls), now()), now() - interval '{BOOTSTRAP_WINDOW}'))::bigint \
         FROM ( \
            SELECT last_synced_at ls FROM catalog.series  WHERE last_synced_at > to_timestamp(0) \
            UNION ALL SELECT last_synced_at FROM catalog.movie   WHERE last_synced_at > to_timestamp(0) \
            UNION ALL SELECT last_synced_at FROM catalog.season  WHERE last_synced_at > to_timestamp(0) \
            UNION ALL SELECT last_synced_at FROM catalog.episode WHERE last_synced_at > to_timestamp(0) \
         ) s"
    ))
    .fetch_one(&state.db)
    .await?;
    Ok(ts)
}

/// Process one feed page: classify records, apply deletes/merges inline, and
/// batch-enqueue the create/updates we actually need.
/// Returns the newest `timeStamp` seen in this page (feed is ascending), so the
/// caller can advance the checkpoint precisely — important when a page cap stops
/// us mid-window.
async fn process_page(
    state: &AppState,
    records: &[Value],
    scope: MirrorScope,
    summary: &mut SyncSummary,
) -> AppResult<Option<i64>> {
    summary.seen += records.len();
    let max_ts = records.iter().filter_map(|r| as_i64(&r["timeStamp"])).max();

    // The feed can list the same id more than once per window (e.g. created then
    // deleted, or updated then merged). Collapse to the LAST event per (type, id)
    // by timeStamp, so we act once on its final state: no fetching a record that
    // was removed after its update (a wasted 404), and no stale soft-delete when a
    // delete is followed by a re-create. Ordering by ts (not "delete always wins")
    // keeps both directions correct.
    // (type, id) -> (timeStamp, methodInt, mergeToId)
    let mut latest: HashMap<(&'static str, i64), (Option<i64>, i64, Option<i64>)> = HashMap::new();
    for rec in records {
        let kind = rec["entityType"]
            .as_str()
            .filter(|s| !s.is_empty())
            .or_else(|| rec["recordType"].as_str().filter(|s| !s.is_empty()));
        let id = as_i64(&rec["recordId"]);
        let (Some(kind), Some(id)) = (kind, id) else {
            summary.skipped += 1;
            continue;
        };
        let Some(table) = table_for(kind) else {
            summary.skipped += 1;
            continue;
        };
        // methodInt: 1=created, 2=updated, 3=deleted (default to update).
        let cand = (as_i64(&rec["timeStamp"]), rec["methodInt"].as_i64().unwrap_or(2), as_i64(&rec["mergeToId"]));
        latest
            .entry((table, id))
            // None ts sorts oldest; on a tie keep the later-seen record.
            .and_modify(|cur| {
                if cand.0 >= cur.0 {
                    *cur = cand;
                }
            })
            .or_insert(cand);
    }

    // Split the reconciled per-id events into deletes (applied inline) and upserts
    // (enqueued for the enrichment worker).
    let mut deletes: Vec<(&'static str, i64, Option<i64>)> = Vec::new();
    // table -> Vec<(id, timeStamp)>
    let mut upserts: HashMap<&'static str, Vec<(i64, Option<i64>)>> = HashMap::new();
    for ((table, id), (ts, method_int, merge_to)) in latest {
        if method_int == 3 {
            deletes.push((table, id, merge_to));
        } else {
            upserts.entry(table).or_default().push((id, ts));
        }
    }

    // Deletes (+ merges) — cheap local DB ops, applied inline. Only count the
    // ones that actually touch a mirrored row; deletes for titles we don't hold
    // are no-ops and counted as skipped (like the upsert path).
    for (table, id, merge_to) in deletes {
        if soft_delete(state, table, id).await? > 0 {
            summary.deleted += 1;
            if let Some(new_id) = merge_to.filter(|&n| n != id) {
                merge(state, table, id, new_id).await?;
                summary.merged += 1;
            }
        } else {
            summary.skipped += 1;
        }
    }

    // Create/updates — one existence+freshness query per table, then enqueue.
    let mut enqueue: Vec<(String, i64, Option<i64>)> = Vec::new();
    for (table, items) in upserts {
        let ids: Vec<i64> = items.iter().map(|(id, _)| *id).collect();
        let rows: Vec<(i64, i64)> = sqlx::query_as(&format!(
            "SELECT id, extract(epoch FROM last_synced_at)::bigint FROM catalog.{table} WHERE id = ANY($1)"
        ))
        .bind(&ids)
        .fetch_all(&state.db)
        .await?;
        let synced: HashMap<i64, i64> = rows.into_iter().collect();

        for (id, ts) in items {
            let keep = match synced.get(&id) {
                // Not mirrored locally.
                None => match table {
                    // Brand-new top-level titles: mirror them in full scope. (The
                    // seed crawl also enumerates these; /updates catches ones added
                    // since the crawl passed their page.)
                    "series" | "movie" => scope == MirrorScope::Full,
                    // Episodes/seasons are mirrored transitively when their parent
                    // series is enriched (list_for_series pulls the whole set), so
                    // fetching one whose parent we don't hold is wasteful — and for
                    // phantom feed records it just 404s. Skip until the parent lands.
                    _ => false,
                },
                // Stub (epoch 0) always; else only if the change is at/after our
                // last fetch of THIS row (per-show dedup).
                Some(&ls) => ls == 0 || ts.is_none_or(|t| t >= ls),
            };
            if keep {
                enqueue.push((table.to_string(), id, ts));
            } else {
                summary.skipped += 1;
            }
        }
    }
    summary.enqueued += queue::enqueue_batch(state, &enqueue).await? as usize;
    Ok(max_ts)
}

/// Repoint user data from a deleted/merged entity to its survivor, then queue the
/// survivor for a full fetch. Wrapped in a transaction for atomicity. Only
/// series/movie/episode carry user references; season merges need no repoint.
async fn merge(state: &AppState, table: &str, old_id: i64, new_id: i64) -> AppResult<()> {
    let mut tx = state.db.begin().await?;
    match table {
        "series" => {
            // Move tracked shows, skipping users who already track the survivor,
            // then drop the leftover duplicates.
            sqlx::query(
                "UPDATE app.user_show u SET series_id = $2 WHERE series_id = $1 \
                 AND NOT EXISTS (SELECT 1 FROM app.user_show x WHERE x.user_id = u.user_id AND x.series_id = $2)",
            )
            .bind(old_id)
            .bind(new_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query("DELETE FROM app.user_show WHERE series_id = $1").bind(old_id).execute(&mut *tx).await?;
            sqlx::query("UPDATE app.watch_event SET series_id = $2 WHERE series_id = $1")
                .bind(old_id)
                .bind(new_id)
                .execute(&mut *tx)
                .await?;
        }
        "movie" => {
            sqlx::query(
                "UPDATE app.user_movie u SET movie_id = $2 WHERE movie_id = $1 \
                 AND NOT EXISTS (SELECT 1 FROM app.user_movie x WHERE x.user_id = u.user_id AND x.movie_id = $2)",
            )
            .bind(old_id)
            .bind(new_id)
            .execute(&mut *tx)
            .await?;
            sqlx::query("DELETE FROM app.user_movie WHERE movie_id = $1").bind(old_id).execute(&mut *tx).await?;
            sqlx::query("UPDATE app.watch_event SET movie_id = $2 WHERE movie_id = $1")
                .bind(old_id)
                .bind(new_id)
                .execute(&mut *tx)
                .await?;
        }
        "episode" => {
            // watch_event.id is the PK, so repointing episode_id can't conflict.
            sqlx::query("UPDATE app.watch_event SET episode_id = $2 WHERE episode_id = $1")
                .bind(old_id)
                .bind(new_id)
                .execute(&mut *tx)
                .await?;
            // Ratings & rewatches are keyed by (user_id, episode_id): move rows
            // whose user doesn't already have the survivor, then drop the dups.
            for table in ["episode_rating", "episode_rewatch"] {
                sqlx::query(&format!(
                    "UPDATE app.{table} r SET episode_id = $2 WHERE episode_id = $1 \
                     AND NOT EXISTS (SELECT 1 FROM app.{table} x WHERE x.user_id = r.user_id AND x.episode_id = $2)"
                ))
                .bind(old_id)
                .bind(new_id)
                .execute(&mut *tx)
                .await?;
                sqlx::query(&format!("DELETE FROM app.{table} WHERE episode_id = $1"))
                    .bind(old_id)
                    .execute(&mut *tx)
                    .await?;
            }
        }
        _ => {}
    }
    tx.commit().await?;

    // Make sure the survivor is fully mirrored.
    queue::enqueue_one(state, table, new_id, "merge").await?;
    Ok(())
}

fn table_for(kind: &str) -> Option<&'static str> {
    let k = kind.to_ascii_lowercase();
    if k.contains("series") {
        Some("series")
    } else if k.contains("movie") {
        Some("movie")
    } else if k.contains("episode") {
        Some("episode")
    } else if k.contains("season") {
        Some("season")
    } else {
        None
    }
}

/// Soft-delete a mirrored row. Returns rows affected (0 if we don't hold it).
async fn soft_delete(state: &AppState, table: &str, id: i64) -> AppResult<u64> {
    // `table` is from a fixed allow-list (table_for), never user input.
    let sql = format!("UPDATE catalog.{table} SET deleted = true WHERE id = $1");
    Ok(sqlx::query(&sql).bind(id).execute(&state.db).await?.rows_affected())
}

async fn get_last_sync_ts(state: &AppState) -> AppResult<Option<i64>> {
    let row: Option<Option<i64>> =
        sqlx::query_scalar("SELECT last_sync_ts FROM catalog.sync_state WHERE id = true")
            .fetch_optional(&state.db)
            .await?;
    Ok(row.flatten())
}

async fn set_last_sync_ts(state: &AppState, ts: i64) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO catalog.sync_state (id, last_sync_ts, updated_at) VALUES (true, $1, now()) \
         ON CONFLICT (id) DO UPDATE SET last_sync_ts = $1, updated_at = now()",
    )
    .bind(ts)
    .execute(&state.db)
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Build an `AppState` against the throwaway test DB, or `None` when
    /// `TEST_DATABASE_URL` is unset (then the test skips, like the integration ones).
    async fn test_state() -> Option<AppState> {
        let _ = dotenvy::from_filename(".env.local");
        let _ = dotenvy::from_filename("../.env.local");
        let url = std::env::var("TEST_DATABASE_URL").ok()?;
        let config = crate::config::Config {
            database_url: url,
            catalog_mode: crate::config::CatalogMode::Proxy,
            mirror_scope: MirrorScope::OnDemand,
            bind_addr: "127.0.0.1:0".into(),
            thetvdb_base_url: "http://localhost".into(),
            thetvdb_api_key: "test".into(),
            jwt_secret: "test-secret".into(),
            public_base_url: "http://localhost".into(),
            web_base_url: "http://localhost".into(),
            allow_public_registration: false,
            smtp: None,
            s3_endpoint: String::new(),
            s3_region: "garage".into(),
            s3_bucket: "artwork".into(),
            s3_access_key: String::new(),
            s3_secret_key: String::new(),
            sync_interval_secs: None,
            thetvdb_max_rps: 35,
            enrich_interval_secs: None,
            enrich_concurrency: 8,
            app_version: "test".into(),
            db_profile: false,
            backend_profile: false,
            db_profile_min_ms: 50,
        };
        Some(AppState::bootstrap(config).await.expect("bootstrap test AppState"))
    }

    async fn queued(state: &AppState, id: i64) -> bool {
        sqlx::query_scalar::<_, i64>(
            "SELECT count(*) FROM catalog.fetch_queue WHERE entity_type='series' AND id=$1",
        )
        .bind(id)
        .fetch_one(&state.db)
        .await
        .unwrap()
            > 0
    }

    async fn purge(state: &AppState, ids: &[i64]) {
        for &id in ids {
            sqlx::query("DELETE FROM catalog.fetch_queue WHERE id=$1").bind(id).execute(&state.db).await.unwrap();
            sqlx::query("DELETE FROM catalog.series WHERE id=$1").bind(id).execute(&state.db).await.unwrap();
        }
    }

    /// The core guarantee behind anchoring `since` at `min(last_synced_at)`: an
    /// update that lands DURING the enrichment window (after a row was enriched)
    /// must be re-queued, while one that predates that row's enrichment must be
    /// skipped as already-captured. Also covers the per-page last-event
    /// reconciliation. Uses unique high ids + targeted cleanup so it can share the
    /// test DB with other suites without a global truncate.
    #[tokio::test]
    async fn sync_catches_updates_during_enrichment_window() {
        let Some(state) = test_state().await else { return }; // skip without TEST_DATABASE_URL
        let ids = [900100_i64, 900200, 900300, 900400];
        purge(&state, &ids).await;

        // Two HELD series enriched at different points in the window:
        //   900100 enriched EARLY (last_synced_at = epoch 1000)
        //   900200 enriched LATE  (last_synced_at = epoch 2000)
        sqlx::query(
            "INSERT INTO catalog.series (id, name, last_synced_at, deleted) VALUES \
               (900100, 'early', to_timestamp(1000), false), \
               (900200, 'late',  to_timestamp(2000), false)",
        )
        .execute(&state.db)
        .await
        .unwrap();

        // One /updates page. Updates to both held series at ts=1500 (a change that
        // happened mid-window), plus two churn pairs for the reconciliation.
        let feed = vec![
            json!({"entityType":"series","recordId":900100,"methodInt":2,"timeStamp":1500}),
            json!({"entityType":"series","recordId":900200,"methodInt":2,"timeStamp":1500}),
            // created then deleted -> net gone -> must NOT enqueue
            json!({"entityType":"series","recordId":900300,"methodInt":1,"timeStamp":1000}),
            json!({"entityType":"series","recordId":900300,"methodInt":3,"timeStamp":2000}),
            // deleted then re-created -> net exists -> must enqueue (full scope)
            json!({"entityType":"series","recordId":900400,"methodInt":3,"timeStamp":1000}),
            json!({"entityType":"series","recordId":900400,"methodInt":1,"timeStamp":2000}),
        ];
        let mut summary = SyncSummary::default();
        process_page(&state, &feed, MirrorScope::Full, &mut summary).await.unwrap();

        // Enrichment-window guarantee:
        assert!(queued(&state, 900100).await, "update AFTER a row's enrichment must be re-queued");
        assert!(!queued(&state, 900200).await, "update PREDATING a row's enrichment is already captured -> skip");
        // Per-page last-event-by-timestamp reconciliation:
        assert!(!queued(&state, 900300).await, "create-then-delete collapses to a delete -> no enqueue, no wasted fetch");
        assert!(queued(&state, 900400).await, "delete-then-create collapses to a create -> enqueue");

        purge(&state, &ids).await;
    }
}
