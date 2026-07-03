//! Mirror populate CLI: fills the local mirror on demand and exits.
//!
//!   cargo run --bin mirror
//!
//! In `MIRROR_SCOPE=full` it first **seed-crawls** the whole catalog (`/series` +
//! `/movies` → stubs, resumable), then **drains** the enrichment queue (stubs →
//! full records). In `on-demand` it just drains whatever's queued. Concurrency
//! comes from ENRICH_CONCURRENCY; throughput is capped by THETVDB_MAX_RPS.

use tracing_subscriber::EnvFilter;

use backend::{
    config::{Config, MirrorScope},
    state::AppState,
    sync,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let config = Config::from_env()?;
    let concurrency = config.enrich_concurrency;
    let scope = config.mirror_scope;
    let state = AppState::bootstrap(config).await?;

    // Full scope: enumerate the whole catalog into stubs first (resumable).
    if scope == MirrorScope::Full {
        tracing::info!("mirror: seed crawl (full scope)");
        let crawl = sync::crawl::run(&state).await?;
        println!("crawl: {}", serde_json::to_string_pretty(&crawl)?);
    }

    let pending = sync::queue::pending_count(&state).await?;
    tracing::info!("mirror: draining queue (pending {pending}, concurrency {concurrency})");
    let summary = sync::enrich::run(&state, concurrency).await?;
    println!("enrich: {}", serde_json::to_string_pretty(&summary)?);
    Ok(())
}
