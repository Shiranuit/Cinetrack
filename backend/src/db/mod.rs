//! Database infrastructure: connection pool + migrations.

use sqlx::{PgPool, postgres::PgPoolOptions};

/// Connect to Postgres and run any pending migrations. The pool is shared by the
/// HTTP server and the background enrichment workers, so it's sized to give the
/// concurrent enrichment fetches (ENRICH_CONCURRENCY) headroom without starving
/// user requests during a heavy mirror backfill.
pub async fn connect_and_migrate(database_url: &str) -> anyhow::Result<PgPool> {
    let pool = PgPoolOptions::new()
        .max_connections(
            std::env::var("DB_MAX_CONNECTIONS").ok().and_then(|v| v.parse().ok()).unwrap_or(20),
        )
        .connect(database_url)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    Ok(pool)
}
