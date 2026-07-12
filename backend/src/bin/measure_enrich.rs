//! Diagnostic: measure where time goes in a full series enrich, per step, with the
//! API-vs-DB split. Runs SERIALLY over a small sample (so numbers are per-series
//! latencies, not throughput) and prints a breakdown + totals.
//!
//!   cargo run --bin measure_enrich                 # 12 tracked series (popular = many languages)
//!   SAMPLE=20 cargo run --bin measure_enrich       # sample size
//!
//! Reads config from env / `.env.local`.

use std::time::Instant;

use tracing_subscriber::EnvFilter;

use backend::{
    catalog::{self, episode::Metrics},
    config::Config,
    state::AppState,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("warn")))
        .init();

    let sample: i64 = std::env::var("SAMPLE").ok().and_then(|s| s.parse().ok()).unwrap_or(12);
    let state = AppState::bootstrap(Config::from_env()?).await?;

    // Popular series (users track them) with episodes — the shows that carry many
    // translation languages, i.e. the expensive enrich case.
    let ids: Vec<i64> = sqlx::query_scalar(
        "SELECT s.id FROM catalog.series s \
         WHERE s.episode_count > 0 \
           AND s.id IN (SELECT DISTINCT series_id FROM app.user_show) \
         ORDER BY s.episode_count DESC LIMIT $1",
    )
    .bind(sample)
    .fetch_all(&state.db)
    .await?;

    println!(
        "{:>9} {:>5} {:>7} {:>4} | {:>9} {:>9} {:>9} {:>9} | {:>6} {:>7}",
        "series", "eps", "refresh", "lang", "episodes", "transl", "  tr_api", "  tr_db", "calls", "tr_rows"
    );
    println!("{}", "-".repeat(96));

    let (mut t_refresh, mut t_eps, mut t_tr, mut t_tr_api, mut t_tr_db) = (0u128, 0u128, 0u128, 0u128, 0u128);
    let (mut n_calls, mut n_rows) = (0u64, 0u64);

    for id in &ids {
        let ep_count: i64 = sqlx::query_scalar("SELECT count(*) FROM catalog.episode WHERE series_id=$1 AND NOT deleted")
            .bind(id).fetch_one(&state.db).await.unwrap_or(0);

        let a = Instant::now();
        let _ = catalog::series::refresh_full(&state, *id).await;
        let refresh = a.elapsed().as_millis();

        let a = Instant::now();
        let _ = catalog::episode::fetch_and_store_episodes(&state, *id, "default", None).await;
        let eps = a.elapsed().as_millis();

        let m = Metrics::default();
        let a = Instant::now();
        let _ = catalog::episode::mirror_translations(&state, *id, Some(&m)).await;
        let tr = a.elapsed().as_millis();
        let (calls, api_us, _ins, ins_us, rows) = m.snapshot();

        println!(
            "{:>9} {:>5} {:>6}ms {:>4} | {:>7}ms {:>7}ms {:>7}ms {:>7}ms | {:>6} {:>7}",
            id, ep_count, refresh, calls, eps, tr, api_us / 1000, ins_us / 1000, calls, rows
        );
        t_refresh += refresh;
        t_eps += eps;
        t_tr += tr;
        t_tr_api += (api_us / 1000) as u128;
        t_tr_db += (ins_us / 1000) as u128;
        n_calls += calls;
        n_rows += rows;
    }

    let n = ids.len().max(1) as u128;
    println!("{}", "-".repeat(96));
    println!("averages per series over {} series:", ids.len());
    println!("  refresh_full          : {:>6} ms", t_refresh / n);
    println!("  fetch_episodes (lean) : {:>6} ms", t_eps / n);
    println!("  mirror_translations   : {:>6} ms  (api {} ms + db {} ms)", t_tr / n, t_tr_api / n, t_tr_db / n);
    println!("  ---");
    println!("  TOTAL enrich / series : {:>6} ms", (t_refresh + t_eps + t_tr) / n);
    println!("  translations share    : {:>5}% of total", 100 * t_tr / (t_refresh + t_eps + t_tr).max(1));
    println!("  avg TheTVDB calls/series (translations only): {}", n_calls / ids.len().max(1) as u64);
    println!("  avg translation rows written/series         : {}", n_rows / ids.len().max(1) as u64);
    Ok(())
}
