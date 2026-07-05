//! One-off backfill: mirror every available-language episode name/overview for
//! every already-mirrored series into `catalog.translation`, so Mirror mode can
//! serve translated episodes offline. Calls TheTVDB (bulk episodes-by-language,
//! once per language a series has), paced by the client's rate limiter. Resumable
//! — re-run to continue; each series is marked done on success.
//!
//!   cargo run --bin backfill_episode_translations
//!   BIN=backfill_episode_translations scripts/run-local.sh   # host-run
//!
//! This is a large sweep for a full mirror (all series × their languages). Let it
//! run to completion, or stop and resume later.

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
    let n = catalog::episode::backfill_all_translations(&state).await?;
    println!("Mirrored episode translations for {n} series.");
    Ok(())
}
