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

    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .init();

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

    let app = web::router(state);

    let listener = tokio::net::TcpListener::bind(&bind_addr).await?;
    tracing::info!("backend listening on {bind_addr}");
    axum::serve(listener, app).await?;

    Ok(())
}
