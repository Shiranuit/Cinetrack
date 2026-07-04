//! Database infrastructure: connection pool + migrations.

use std::{str::FromStr, time::Duration};

use sqlx::{
    ConnectOptions, PgPool,
    postgres::{PgConnectOptions, PgPoolOptions},
};

/// Connect to Postgres and run any pending migrations. The pool is shared by the
/// HTTP server and the background enrichment workers, so it's sized to give the
/// concurrent enrichment fetches (ENRICH_CONCURRENCY) headroom without starving
/// user requests during a heavy mirror backfill.
pub async fn connect_and_migrate(database_url: &str) -> anyhow::Result<PgPool> {
    let mut opts = PgConnectOptions::from_str(database_url)?;
    if crate::config::env_flag("DB_PROFILE") {
        // Under DB_PROFILE, log statements SLOWER than the threshold at WARN (visible
        // at the default log level) and hide the rest at TRACE — so the log carries
        // only expensive queries, not thousands of sub-millisecond ones.
        let min_ms = std::env::var("DB_PROFILE_MIN_MS").ok().and_then(|v| v.parse().ok()).unwrap_or(50);
        opts = opts
            .log_statements(log::LevelFilter::Trace)
            .log_slow_statements(log::LevelFilter::Warn, Duration::from_millis(min_ms));
    }
    // (When not profiling, sqlx's defaults still WARN on any statement slower than 1s.)
    let pool = PgPoolOptions::new()
        .max_connections(
            std::env::var("DB_MAX_CONNECTIONS").ok().and_then(|v| v.parse().ok()).unwrap_or(20),
        )
        .connect_with(opts)
        .await?;
    sqlx::migrate!("./migrations").run(&pool).await?;
    Ok(pool)
}
