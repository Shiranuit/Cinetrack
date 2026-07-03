//! Enrichment worker: drains `catalog.fetch_queue`, turning stubs / flagged
//! entities into fully-mirrored records via TheTVDB `/extended` (+ episodes for
//! series). See docs/thetvdb-sync-redesign.md §7.
//!
//! Concurrency is a pool of `concurrency` long-lived workers that each
//! claim-and-process in a loop until the queue drains; the client's global rate
//! pacer caps total throughput. A continuous pool (rather than a per-batch
//! barrier) keeps the pacer's queue continuously fed, so effective throughput
//! tracks `THETVDB_MAX_RPS` instead of being pinned to `batch / slowest-item`.
//! Note: this worker calls TheTVDB regardless of `CATALOG_MODE` — building the
//! mirror is its whole job. Don't enable it (interval / `bin/mirror`) if you want
//! zero outbound calls.

use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use tokio::task::JoinSet;

use crate::{
    catalog,
    error::AppResult,
    state::AppState,
    sync::queue,
    thetvdb::{Priority, with_priority},
};

/// Give up on an item after this many failed attempts.
const MAX_ATTEMPTS: i32 = 4;

/// Items each worker claims per DB round-trip. Small so work stays evenly spread
/// across workers (smooth tail drain) while amortizing the claim query.
const CLAIM_BATCH: i64 = 8;

/// Log progress (and query remaining depth) every this many enriched items.
const PROGRESS_EVERY: usize = 500;

/// Cross-worker tallies, summed into the final [`EnrichSummary`].
#[derive(Default)]
struct Counters {
    enriched: AtomicUsize,
    failed: AtomicUsize,
    dropped: AtomicUsize,
    not_found: AtomicUsize,
}

#[derive(Debug, Default, serde::Serialize)]
pub struct EnrichSummary {
    pub swept: u64,       // stubs swept into the queue at the start of this run
    pub enriched: usize,
    pub failed: usize,    // transient fetch errors (re-queued unless past MAX_ATTEMPTS)
    pub dropped: usize,   // failures past MAX_ATTEMPTS, given up on
    pub not_found: usize, // phantom feed records (upstream 404) — dropped, not retried
}

/// Drain the queue until empty (first sweeping existing stubs in). `concurrency`
/// long-lived workers run in parallel; the global rate pacer caps throughput.
pub async fn run(state: &AppState, concurrency: usize) -> AppResult<EnrichSummary> {
    let swept = queue::enqueue_stubs(state).await?;

    let pending = queue::pending_count(state).await?;
    if pending > 0 {
        tracing::info!("enrich: draining {pending} queued item(s) (concurrency {concurrency})");
    }

    // A pool of workers, each claim-process-repeating until the queue is empty.
    // This keeps the rate pacer's wait-queue continuously fed (no per-batch
    // barrier stalls), so we sustain ~THETVDB_MAX_RPS rather than being pinned to
    // batch_size / slowest-item.
    let counters = Arc::new(Counters::default());
    let mut set = JoinSet::new();
    for _ in 0..concurrency.max(1) {
        let st = state.clone();
        let c = counters.clone();
        // Low priority so these background fetches yield to interactive ones.
        // (Each spawned task must set its own scope — task-locals don't cross spawn.)
        set.spawn(with_priority(Priority::Low, async move { worker(st, c).await }));
    }
    while let Some(joined) = set.join_next().await {
        joined.expect("enrich worker panicked")?;
    }

    let summary = EnrichSummary {
        swept,
        enriched: counters.enriched.load(Ordering::Relaxed),
        failed: counters.failed.load(Ordering::Relaxed),
        dropped: counters.dropped.load(Ordering::Relaxed),
        not_found: counters.not_found.load(Ordering::Relaxed),
    };
    // Only log a summary when something actually happened (event-driven wakeups
    // that find an empty queue stay quiet).
    if summary.enriched + summary.failed + summary.dropped + summary.not_found + summary.swept as usize > 0 {
        tracing::info!("enrich: {summary:?}");
    }
    Ok(summary)
}

/// One worker: claim a small batch, process each item, repeat until the queue is
/// empty. A worker exits only on an empty claim; while any worker is still
/// looping it picks up items requeued by failures, so nothing is lost (and the
/// heartbeat/`/updates` re-sweeps anything a late requeue leaves behind).
async fn worker(state: AppState, counters: Arc<Counters>) -> AppResult<()> {
    loop {
        let items = queue::claim(&state, CLAIM_BATCH).await?;
        if items.is_empty() {
            break;
        }
        for item in items {
            match enrich_one(&state, &item).await {
                Ok(()) => {
                    let done = counters.enriched.fetch_add(1, Ordering::Relaxed) + 1;
                    if done % PROGRESS_EVERY == 0 {
                        let remaining = queue::pending_count(&state).await?;
                        tracing::info!("enrich: {done} done, {remaining} remaining");
                    }
                }
                // A phantom feed record (created then removed/merged upstream):
                // `/extended` 404s and never will resolve, so drop it immediately
                // instead of burning retries on it.
                Err(crate::error::AppError::NotFound) => {
                    counters.not_found.fetch_add(1, Ordering::Relaxed);
                    tracing::debug!("enrich {} {} not found upstream, dropping", item.entity_type, item.id);
                }
                Err(e) => {
                    tracing::warn!("enrich {} {} failed: {e}", item.entity_type, item.id);
                    counters.failed.fetch_add(1, Ordering::Relaxed);
                    if !queue::requeue_failed(&state, &item, MAX_ATTEMPTS).await? {
                        counters.dropped.fetch_add(1, Ordering::Relaxed);
                        tracing::warn!("enrich {} {} dropped after {} attempts", item.entity_type, item.id, item.attempts + 1);
                    }
                }
            }
        }
    }
    Ok(())
}

/// Fully populate one entity from TheTVDB.
async fn enrich_one(state: &AppState, item: &queue::QueueItem) -> AppResult<()> {
    match item.entity_type.as_str() {
        "series" => {
            catalog::series::refresh_full(state, item.id).await?;
            // Episodes (default season order) for offline completeness — best
            // effort so a missing/edge episode set doesn't fail the whole item.
            if let Err(e) = catalog::episode::list_for_series(state, item.id, "default", None).await {
                tracing::debug!("enrich series {} episodes skipped: {e}", item.id);
            }
        }
        "movie" => catalog::movie::refresh_full(state, item.id).await?,
        "season" => catalog::season::refresh(state, item.id).await?,
        "episode" => catalog::episode::refresh(state, item.id).await?,
        other => tracing::debug!("enrich: unknown entity_type '{other}', skipping"),
    }
    Ok(())
}
