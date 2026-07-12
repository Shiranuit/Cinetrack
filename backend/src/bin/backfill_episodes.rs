//! Fast repair CLI: re-pull ONLY the episode list for series whose mirror copy is
//! behind upstream (the Mirror-mode enrich bug froze episode lists at the seed). Unlike
//! `resync_stale_episodes` — which marks stubs and lets the enrich worker do a FULL
//! re-enrich (metadata + episodes + per-language episode translations, hundreds of
//! TheTVDB calls per series) — this calls `fetch_and_store_episodes` directly: ~1 call
//! per series. So it finishes in minutes and barely touches the rate limit. Metadata
//! and translations refresh later through normal enrich; the episode list (what the
//! calendar/"missing episodes" need) is fixed immediately.
//!
//! Target set (default): series whose upstream `last_updated` is newer than our last
//! episode sync. Env knobs:
//!
//!   cargo run --bin backfill_episodes                 # all series with episodes behind upstream
//!   SINCE_DAYS=7   cargo run --bin backfill_episodes  # ... only upstream changes in the last N days
//!   TRACKED_ONLY=1 cargo run --bin backfill_episodes  # ... only series at least one user tracks
//!   CONCURRENCY=32 cargo run --bin backfill_episodes  # override the in-flight fetch count
//!
//! Reads config from env / `.env.local` like the server. Safe to run alongside the
//! server, but it uses its OWN rate pacer — to stay under THETVDB_MAX_RPS overall,
//! prefer running it when the server's sync/enrich is idle.

use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

use tokio::{sync::Semaphore, task::JoinSet};
use tracing_subscriber::EnvFilter;

use backend::{catalog, config::Config, state::AppState};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let since_days: Option<i64> = std::env::var("SINCE_DAYS").ok().and_then(|s| s.parse().ok());
    let tracked_only = std::env::var("TRACKED_ONLY").is_ok_and(|v| v == "1" || v.eq_ignore_ascii_case("true"));

    let config = Config::from_env()?;
    let concurrency: usize = std::env::var("CONCURRENCY")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(config.enrich_concurrency)
        .max(1);
    let state = AppState::bootstrap(config).await?;

    // "Episodes behind upstream": metadata synced fine, only the episode list was
    // skipped, so last_updated > episodes_synced_at.
    let mut sql = String::from(
        "SELECT id FROM catalog.series WHERE last_updated > episodes_synced_at",
    );
    if let Some(days) = since_days {
        sql.push_str(&format!(" AND last_updated >= now() - interval '{days} days'"));
    }
    if tracked_only {
        sql.push_str(
            " AND id IN (SELECT DISTINCT series_id FROM app.user_show \
               WHERE is_followed OR status IS NOT NULL)",
        );
    }
    let ids: Vec<i64> = sqlx::query_scalar(&sql).fetch_all(&state.db).await?;
    let total = ids.len();
    tracing::info!(
        "backfill_episodes: {total} series to refresh (concurrency {concurrency}, since_days={since_days:?}, tracked_only={tracked_only})"
    );
    if total == 0 {
        println!("nothing to do — no series with episodes behind upstream");
        return Ok(());
    }

    let sem = Arc::new(Semaphore::new(concurrency));
    let (ok, failed) = (Arc::new(AtomicUsize::new(0)), Arc::new(AtomicUsize::new(0)));
    let mut set = JoinSet::new();
    for id in ids {
        let st = state.clone();
        let permit = sem.clone().acquire_owned().await?;
        let (ok, failed) = (ok.clone(), failed.clone());
        set.spawn(async move {
            let _permit = permit; // released on drop, capping in-flight fetches
            match catalog::episode::fetch_and_store_episodes(&st, id, "default", None).await {
                Ok(()) => {
                    let done = ok.fetch_add(1, Ordering::Relaxed) + 1;
                    if done % 200 == 0 {
                        tracing::info!("backfill_episodes: {done} done");
                    }
                }
                Err(e) => {
                    failed.fetch_add(1, Ordering::Relaxed);
                    tracing::warn!("backfill_episodes: series {id} failed: {e}");
                }
            }
        });
    }
    while let Some(joined) = set.join_next().await {
        joined.expect("backfill task panicked");
    }

    let (ok, failed) = (ok.load(Ordering::Relaxed), failed.load(Ordering::Relaxed));
    tracing::info!("backfill_episodes: done — {ok} refreshed, {failed} failed (of {total})");
    println!("refreshed {ok} series' episode lists, {failed} failed (of {total})");
    Ok(())
}
