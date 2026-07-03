//! One-off backfill: flag library shows whose TheTVDB id 404s as `unavailable`,
//! so the library hides dead cards left over from older imports.
//!
//!   cargo run --bin backfill_unavailable
//!
//! Reads config from env / `.env.local` like the server.

use tracing_subscriber::EnvFilter;

use backend::{config::Config, import, state::AppState};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let config = Config::from_env()?;
    let state = AppState::bootstrap(config).await?;

    let (ok, flagged) = import::backfill_unavailable(&state).await;
    println!("resolved {ok}, flagged/failed {flagged}");
    Ok(())
}
