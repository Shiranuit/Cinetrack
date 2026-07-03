//! One-off backfill: re-derive filter facets (genres/tags/companies + season/
//! episode counts) for every already-mirrored series from its stored `raw`. No
//! TheTVDB calls. Run after adding the facet tables (migration 0011).
//!
//!   cargo run --bin backfill_facets
//!   BIN=backfill_facets scripts/run-local.sh   # host-run

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
    let n = catalog::facets::backfill(&state).await?;
    println!("Backfilled facets for {n} series.");
    Ok(())
}
