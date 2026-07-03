//! The `catalog.fetch_queue` — work items for the enrichment worker.
//!
//! Contract (see docs/thetvdb-sync-redesign.md §7):
//! - **claim** removes a batch atomically with `FOR UPDATE SKIP LOCKED`, so
//!   concurrent workers never grab the same row and no lock is held across the
//!   (slow) network fetch.
//! - **delete-on-success** is implicit: claiming removes the row; only failures
//!   are re-inserted (with `attempts + 1`), up to a cap. A worker crash mid-fetch
//!   loses at most a few items, which the stub sweep / `/updates` re-discovers.
//! - enqueue is **batched** and dedup'd by `PRIMARY KEY(entity_type, id)`.
//!
//! `source_updated_at` is carried as a Unix epoch (seconds) since sqlx has no
//! chrono/time feature enabled here; it's advisory only.

use crate::{error::AppResult, state::AppState};

/// A claimed unit of enrichment work.
#[derive(Debug, Clone)]
pub struct QueueItem {
    pub entity_type: String,
    pub id: i64,
    pub reason: Option<String>,
    pub source_updated_at: Option<i64>, // unix epoch (advisory)
    pub attempts: i32,
}

/// Atomically claim up to `n` items (FIFO by `enqueued_at`), removing them from
/// the queue. Skips rows locked by other workers.
pub async fn claim(state: &AppState, n: i64) -> AppResult<Vec<QueueItem>> {
    let rows = sqlx::query_as::<_, (String, i64, Option<String>, Option<i64>, i32)>(
        "DELETE FROM catalog.fetch_queue \
         WHERE (entity_type, id) IN ( \
             SELECT entity_type, id FROM catalog.fetch_queue \
             ORDER BY enqueued_at \
             FOR UPDATE SKIP LOCKED \
             LIMIT $1 \
         ) \
         RETURNING entity_type, id, reason, \
                   extract(epoch FROM source_updated_at)::bigint AS source_updated_at, attempts",
    )
    .bind(n)
    .fetch_all(&state.db)
    .await?;

    Ok(rows
        .into_iter()
        .map(|(entity_type, id, reason, source_updated_at, attempts)| QueueItem {
            entity_type,
            id,
            reason,
            source_updated_at,
            attempts,
        })
        .collect())
}

/// Re-enqueue a failed item with an incremented attempt count, unless it has hit
/// `max_attempts` (then it's dropped and logged by the caller). Returns whether
/// it was re-queued.
pub async fn requeue_failed(state: &AppState, item: &QueueItem, max_attempts: i32) -> AppResult<bool> {
    if item.attempts + 1 >= max_attempts {
        return Ok(false);
    }
    sqlx::query(
        "INSERT INTO catalog.fetch_queue (entity_type, id, reason, source_updated_at, attempts, enqueued_at) \
         VALUES ($1, $2, $3, to_timestamp($4), $5, now()) \
         ON CONFLICT (entity_type, id) DO UPDATE SET attempts = catalog.fetch_queue.attempts + 1, enqueued_at = now()",
    )
    .bind(&item.entity_type)
    .bind(item.id)
    .bind(&item.reason)
    .bind(item.source_updated_at)
    .bind(item.attempts + 1)
    .execute(&state.db)
    .await?;
    Ok(true)
}

/// Enqueue one item with a specific reason (upsert; keeps newer `source_updated_at`).
pub async fn enqueue_one(state: &AppState, entity_type: &str, id: i64, reason: &str) -> AppResult<()> {
    enqueue_batch_reason(state, &[(entity_type.to_string(), id, None)], reason).await?;
    Ok(())
}

/// Enqueue a batch of `(entity_type, id, source_updated_at_epoch)` (reason
/// `update`) in one insert. Dedup'd by PK; on conflict keeps the newer
/// `source_updated_at` and re-stamps `enqueued_at`. Returns rows inserted/updated.
pub async fn enqueue_batch(state: &AppState, items: &[(String, i64, Option<i64>)]) -> AppResult<u64> {
    enqueue_batch_reason(state, items, "update").await
}

async fn enqueue_batch_reason(state: &AppState, items: &[(String, i64, Option<i64>)], reason: &str) -> AppResult<u64> {
    if items.is_empty() {
        return Ok(0);
    }
    // Dedupe by (entity_type, id): a single INSERT … ON CONFLICT DO UPDATE cannot
    // affect the same row twice, and the /updates feed can list an entity more
    // than once per page. Keep the newest source_updated_at (None < Some).
    let mut latest: std::collections::HashMap<(&str, i64), Option<i64>> = std::collections::HashMap::new();
    for (et, id, ts) in items {
        let slot = latest.entry((et.as_str(), *id)).or_insert(*ts);
        if *ts > *slot {
            *slot = *ts;
        }
    }
    let mut types: Vec<&str> = Vec::with_capacity(latest.len());
    let mut ids: Vec<i64> = Vec::with_capacity(latest.len());
    let mut srcs: Vec<Option<i64>> = Vec::with_capacity(latest.len());
    for ((et, id), ts) in &latest {
        types.push(et);
        ids.push(*id);
        srcs.push(*ts);
    }

    let n = sqlx::query(
        "INSERT INTO catalog.fetch_queue (entity_type, id, reason, source_updated_at) \
         SELECT et, i, $4, to_timestamp(su) \
         FROM UNNEST($1::text[], $2::bigint[], $3::bigint[]) AS t(et, i, su) \
         ON CONFLICT (entity_type, id) DO UPDATE SET \
           source_updated_at = GREATEST(catalog.fetch_queue.source_updated_at, EXCLUDED.source_updated_at), \
           enqueued_at = now()",
    )
    .bind(&types)
    .bind(&ids)
    .bind(&srcs)
    .bind(reason)
    .execute(&state.db)
    .await?
    .rows_affected();
    if n > 0 {
        state.enrich_notify.notify_one(); // wake the enrichment worker
    }
    Ok(n)
}

/// Sweep un-enriched stubs (rows `store_stub` pinned to the epoch) into the queue.
/// Cheap, idempotent bulk insert; dedup'd by PK. Returns rows added.
pub async fn enqueue_stubs(state: &AppState) -> AppResult<u64> {
    let mut added = 0;
    for entity in ["series", "movie"] {
        let n = sqlx::query(&format!(
            "INSERT INTO catalog.fetch_queue (entity_type, id, reason) \
             SELECT '{entity}', id, 'stub' FROM catalog.{entity} \
             WHERE last_synced_at = to_timestamp(0) \
             ON CONFLICT (entity_type, id) DO NOTHING"
        ))
        .execute(&state.db)
        .await?
        .rows_affected();
        added += n;
    }
    if added > 0 {
        state.enrich_notify.notify_one();
    }
    Ok(added)
}

/// Current number of pending items (for logging / observability).
pub async fn pending_count(state: &AppState) -> AppResult<i64> {
    Ok(sqlx::query_scalar("SELECT count(*) FROM catalog.fetch_queue").fetch_one(&state.db).await?)
}
