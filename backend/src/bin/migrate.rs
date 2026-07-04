//! Apply database migrations without starting the server. Lets you migrate + seed
//! while the backend is offline, so its sync worker doesn't race a catalog import.
//!
//!   docker compose -f production.docker-compose.yaml --env-file .env.production \
//!     run --rm backend migrate
//!   BIN=migrate scripts/run-local.sh                                   # host-run (dev)
//!
//! Migrations are embedded at build time (sqlx::migrate!), so this needs only a
//! reachable DATABASE_URL. The server also applies them on boot; this just lets you
//! do it first (then seed, then start the backend).

use tracing_subscriber::EnvFilter;

use backend::{config::Config, db};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

    let config = Config::from_env()?;
    let _pool = db::connect_and_migrate(&config.database_url).await?;
    println!("migrations applied");
    Ok(())
}
