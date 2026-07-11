//! One-off backfill: attribute pre-existing GDPR-import watch events to a synthetic
//! "legacy" import batch, so a later re-import replaces them instead of duplicating.
//! Rows imported before import batching have no `import_id`; this tags the ones that
//! look like import artifacts (dense created_at bursts — hundreds of rows at one
//! instant), leaving the sparse, manually-added watches alone. Only considers events
//! created BEFORE import batching shipped (the gdpr_import migration's applied time),
//! so it can never sweep a watch added afterwards. Idempotent — safe to re-run; only
//! picks up still-untagged rows.
//!
//!   cargo run --bin backfill_import_tags
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

    let tagged = import::retro_tag_legacy_imports(&state).await?;
    println!("retro-tagged {tagged} legacy import watch event(s)");
    Ok(())
}
