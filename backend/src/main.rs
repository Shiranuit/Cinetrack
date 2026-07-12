use std::time::Duration;

use tracing_subscriber::EnvFilter;

use backend::{
    config::{Config, MirrorScope},
    state::AppState,
    sync, web,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load env for local dev. `.env.local` (git-ignored, holds secrets like the
    // TheTVDB API key) takes precedence, then `.env`. In containers these files
    // are absent and real env vars are used.
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::dotenv();

    // Base filter from RUST_LOG, else info. DB_PROFILE's slow-query logs come through
    // sqlx at WARN (configured on the pool, see `db`), so they're visible at the
    // default level without widening here. BACKEND_PROFILE raises our own logs to debug.
    let mut filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    if backend::config::env_flag("BACKEND_PROFILE") {
        filter = filter.add_directive("backend=debug".parse().expect("static directive"));
    }
    tracing_subscriber::fmt().with_env_filter(filter).init();

    let config = Config::from_env()?;
    let bind_addr = config.bind_addr.clone();

    let state = AppState::bootstrap(config).await?;
    tracing::info!(
        "catalog mode: {:?} · mirror scope: {:?}",
        state.config.catalog_mode,
        state.config.mirror_scope
    );

    // Full-scope seed crawl: enumerate the entire TheTVDB catalog (`/series` +
    // `/movies`) into lightweight stubs, so the mirror grows to the whole catalog
    // — not just entities touched on demand or reported by the 30-day `/updates`
    // window. Resumable via `catalog.crawl_state` and idempotent: once a type is
    // exhausted it's marked done and later starts skip it (cheap no-op). The
    // enrichment worker below then fills the stubs. Runs in the background so the
    // server serves immediately; brand-new titles keep arriving via `/updates`.
    if state.config.mirror_scope == MirrorScope::Full {
        let worker = state.clone();
        tokio::spawn(async move {
            tracing::info!("seed crawl starting (full scope; resumable)");
            match sync::crawl::run(&worker).await {
                Ok(s) => tracing::info!("seed crawl finished: {s:?}"),
                Err(e) => tracing::error!("seed crawl failed: {e}"),
            }
            // Sweep the freshly-created stubs into the enrichment queue now.
            worker.enrich_notify.notify_one();
        });
    }

    // Optional background /updates sync worker.
    if let Some(secs) = state.config.sync_interval_secs {
        let worker = state.clone();
        tracing::info!("sync worker enabled (every {secs}s)");
        tokio::spawn(async move {
            let mut ticker = tokio::time::interval(Duration::from_secs(secs));
            loop {
                ticker.tick().await;
                if let Err(e) = sync::run_once(&worker).await {
                    tracing::error!("sync run failed: {e}");
                }
            }
        });
    }

    // Optional background enrichment worker: drains the fetch queue (stubs → full
    // records) as **Low priority**, so it yields to interactive requests. It is
    // event-driven — woken immediately whenever something is enqueued (search/
    // discover stubs, /updates changes) — with the interval only as a fallback
    // heartbeat to catch enqueues from other processes (e.g. `bin/sync`). Calls
    // TheTVDB, so leave it off (`ENRICH_INTERVAL_SECS` unset) for a pure-offline
    // deployment; `bin/mirror` does an on-demand bulk fill.
    if let Some(secs) = state.config.enrich_interval_secs {
        let worker = state.clone();
        let concurrency = state.config.enrich_concurrency;
        tracing::info!("enrichment worker enabled (event-driven; fallback every {secs}s, concurrency {concurrency})");
        tokio::spawn(async move {
            loop {
                if let Err(e) = sync::enrich::run(&worker, concurrency).await {
                    tracing::error!("enrichment run failed: {e}");
                }
                // Sleep until new work arrives or the fallback heartbeat fires.
                tokio::select! {
                    _ = worker.enrich_notify.notified() => {}
                    _ = tokio::time::sleep(Duration::from_secs(secs)) => {}
                }
            }
        });
    }

    // Optional background-work profiler: with BACKEND_PROFILE=1, log queue throughput,
    // TheTVDB API rate (+ how much time is spent WAITING in the pacer vs the actual
    // HTTP round-trip — high wait = at the RPS ceiling, ~0 wait = pacer starved so the
    // bottleneck is elsewhere), 429 retry rate, and catalog DB-write rate/latency.
    if state.config.backend_profile {
        let p = state.clone();
        tokio::spawn(async move {
            const WINDOW: u64 = 15;
            let (mut la, mut ls) = (p.tvdb.stats().snapshot(), p.profile.snapshot());
            loop {
                tokio::time::sleep(Duration::from_secs(WINDOW)).await;
                let (a, s) = (p.tvdb.stats().snapshot(), p.profile.snapshot());
                let (dcalls, dwait, dhttp, dretry) =
                    (a.0 - la.0, a.1 - la.1, a.2 - la.2, a.3 - la.3);
                let (denr, ddbw, ddbus) = (s.0 - ls.0, s.1 - ls.1, s.2 - ls.2);
                (la, ls) = (a, s);
                if dcalls == 0 && denr == 0 && ddbw == 0 {
                    continue; // idle window — stay quiet
                }
                let qdepth: i64 = sqlx::query_scalar("SELECT count(*) FROM catalog.fetch_queue")
                    .fetch_one(&p.db)
                    .await
                    .unwrap_or(-1);
                let w = WINDOW as f64;
                let avg = |num: u64, den: u64| if den > 0 { num / den / 1000 } else { 0 };
                tracing::info!(
                    "profile[{WINDOW}s]: enrich {:.1}/s (queue {qdepth}) | \
                     api {:.1}/s (http {}ms, pacer-wait {}ms) retries {dretry} ({:.2}/s) | \
                     db {:.1} writes/s ({}ms avg)",
                    denr as f64 / w,
                    dcalls as f64 / w,
                    avg(dhttp, dcalls),
                    avg(dwait, dcalls),
                    dretry as f64 / w,
                    ddbw as f64 / w,
                    avg(ddbus, ddbw),
                );
            }
        });
    }

    let app = web::router(state);

    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    tracing::info!("backend listening on {bind_addr}");
    axum::serve(listener, app).await?;

    Ok(())
}
