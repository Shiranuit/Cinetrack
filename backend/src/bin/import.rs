//! GDPR import CLI: loads a TV Time export `.zip` into the database.
//!
//!   cargo run --bin import -- /path/to/tvtime-export.zip
//!
//! Idempotent — safe to re-run. Reads config from env / `.env.local` like the
//! server.

use tracing_subscriber::EnvFilter;

use backend::{config::Config, import, state::AppState};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let zip_path = std::env::args().nth(1).ok_or_else(|| {
        anyhow::anyhow!("usage: import <path-to-tvtime-export.zip> [target-user-id]")
    })?;
    // Optional 2nd arg: import into an existing user id (repair/refresh) instead
    // of creating a fresh account from the export's original id.
    let target_user: Option<uuid::Uuid> = std::env::args().nth(2).map(|a| a.parse()).transpose()?;

    let config = Config::from_env()?;
    let state = AppState::bootstrap(config).await?;

    let summary = match target_user {
        Some(uid) => {
            tracing::info!("importing GDPR export from {zip_path} into existing user {uid}");
            import::run_zip_into(&state, &zip_path, uid).await?
        }
        None => {
            tracing::info!("importing GDPR export from {zip_path}");
            import::run(&state, &zip_path).await?
        }
    };

    println!("\nImport complete:\n{}", serde_json::to_string_pretty(&summary)?);
    Ok(())
}
