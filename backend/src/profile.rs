//! Query/request profiling, gated by the `DB_PROFILE` / `BACKEND_PROFILE` config
//! flags (see [`crate::config`]). Off by default and effectively free: callers
//! guard on `config.db_profile` before doing any profiling work.
//!
//! Two layers:
//!   * **Statement timing** (global): when `DB_PROFILE` is on, the log filter is
//!     widened so sqlx's own per-statement timing surfaces — every query logs its
//!     SQL and elapsed time, no call-site changes needed. Wired in `main`.
//!   * **EXPLAIN ANALYZE** (targeted): the *expensive* read queries call
//!     [`explain`] so their query plan (real row counts, timing, buffer hits) is
//!     logged. Cheap queries are intentionally left out.

use std::time::Instant;

use sqlx::{PgPool, Postgres, Row, postgres::PgArguments, query::Query};

/// Wrap a statement in `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`. Prefix only — bind the
/// SAME parameters as the real query onto a `sqlx::query(&explain_sql(sql))`.
pub fn explain_sql(sql: &str) -> String {
    format!("EXPLAIN (ANALYZE, BUFFERS, VERBOSE) {sql}")
}

/// Run an already-bound `EXPLAIN …` query and log the plan under the `db_profile`
/// target, labelled by call site. Best-effort: any error is logged, never
/// propagated — profiling must never break a request. Only call when
/// `config.db_profile` is set (the caller also skips building the query otherwise).
pub async fn explain(db: &PgPool, label: &str, explain_query: Query<'_, Postgres, PgArguments>) {
    let start = Instant::now();
    match explain_query.fetch_all(db).await {
        Ok(rows) => {
            let plan: String = rows
                .iter()
                .filter_map(|r| r.try_get::<String, _>(0).ok())
                .collect::<Vec<_>>()
                .join("\n");
            tracing::info!(
                target: "db_profile",
                "EXPLAIN [{label}] (analyze took {} ms):\n{plan}",
                start.elapsed().as_millis()
            );
        }
        Err(e) => tracing::warn!(target: "db_profile", "EXPLAIN [{label}] failed: {e}"),
    }
}
