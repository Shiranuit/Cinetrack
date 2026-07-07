//! One-off backfill: re-fetch the `?meta=translations` bundle for every series and
//! movie, re-ingesting the REAL translated names (not TheTVDB's `isAlias` romanized
//! aliases) into `catalog.translation`, and caching the raw bundle in
//! `raw_translations` so future layout changes can re-derive from local data instead
//! of re-querying all of TheTVDB. Calls TheTVDB (one bundled request per entity),
//! paced by the client's rate limiter. Resumable: each entity is marked done once its
//! `raw_translations` is set, so re-run to continue.
//!
//!   cargo run --bin backfill_series_movie_translations              # full sweep
//!   cargo run --bin backfill_series_movie_translations -- 358612 305074   # only these ids
//!   BIN=backfill_series_movie_translations scripts/run-local.sh    # host-run
//!
//! With no args it's a large sweep for a full mirror (all series + all movies); let it
//! run to completion, or stop and resume later. With id args it repairs just those
//! (series or movie, auto-detected) — handy for a canary run. Tune parallelism with
//! BACKFILL_CONCURRENCY.

use tracing_subscriber::EnvFilter;

use backend::{catalog, config::Config, state::AppState};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let state = AppState::bootstrap(Config::from_env()?).await?;

    // Positional args = specific catalog ids to repair; none = full resumable sweep.
    let ids: Vec<i64> = std::env::args().skip(1).filter_map(|a| a.parse().ok()).collect();
    let n = if ids.is_empty() {
        catalog::translation::backfill_all_bundles(&state).await?
    } else {
        catalog::translation::backfill_ids(&state, &ids).await?
    };
    println!("Backfilled name/overview translation bundles for {n} entities.");
    Ok(())
}
