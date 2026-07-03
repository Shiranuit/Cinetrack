//! Catalog sync CLI: runs one `/updates` sync pass and exits (cron-friendly).
//!
//!   cargo run --bin sync
//!
//! Reads config from env / `.env.local` like the server.

use tracing_subscriber::EnvFilter;

use backend::{config::Config, state::AppState, sync};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let config = Config::from_env()?;
    let state = AppState::bootstrap(config).await?;

    let summary = sync::run_once(&state).await?;
    println!("{}", serde_json::to_string_pretty(&summary)?);
    Ok(())
}
