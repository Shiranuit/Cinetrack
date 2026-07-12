//! Repair CLI: re-sync series whose mirrored episode list went stale under the
//! Mirror-mode enrich bug (episode lists were frozen at the initial seed, so
//! newly-aired/added episodes never landed).
//!
//! It doesn't fetch anything itself — it just resets each target series' sync marker
//! to the stub value (`last_synced_at = to_timestamp(0)`). The running backend's
//! enrich worker sweeps stubs (`enqueue_stubs`) on its next cycle (≤30s, or on any
//! wakeup) and fully re-enriches them, which now re-pulls the whole episode list
//! (incl. future episodes) via the fixed `fetch_and_store_episodes`. If no server is
//! running, `cargo run --bin mirror` drains the queue instead. Idempotent.
//!
//! Target set (default): series whose upstream `last_updated` is newer than our last
//! episode sync — i.e. episodes that are actually behind. Env knobs narrow it:
//!
//!   cargo run --bin resync_stale_episodes                 # all series with episodes behind upstream
//!   SINCE_DAYS=7   cargo run --bin resync_stale_episodes  # ... only upstream changes in the last N days
//!   TRACKED_ONLY=1 cargo run --bin resync_stale_episodes  # ... only series at least one user tracks
//!
//! Reads config from env / `.env.local` like the server.

use tracing_subscriber::EnvFilter;

use backend::{config::Config, state::AppState};

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
    let state = AppState::bootstrap(config).await?;

    // "Episodes behind upstream" is the exact victim set: the series metadata synced
    // fine, only the episode list was skipped, so last_updated > episodes_synced_at.
    let mut sql = String::from(
        "UPDATE catalog.series SET last_synced_at = to_timestamp(0) \
         WHERE last_updated > episodes_synced_at",
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

    let reset = sqlx::query(&sql).execute(&state.db).await?.rows_affected();

    // Nudge our own handle's notify in case a server shares this process's state (it
    // doesn't here — the bin is standalone — but harmless and documents intent).
    state.enrich_notify.notify_one();

    tracing::info!(
        "resync_stale_episodes: marked {reset} series for re-enrich (since_days={since_days:?}, tracked_only={tracked_only})"
    );
    println!(
        "marked {reset} series for re-sync — the running backend's enrich sweep will re-pull their episodes \
         (or run `cargo run --bin mirror` to drain now)"
    );
    Ok(())
}
