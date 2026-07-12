use std::sync::{
    Arc,
    atomic::{AtomicU64, Ordering},
};

use sqlx::PgPool;
use tokio::sync::Notify;

use crate::{
    auth::ratelimit::RateLimiter, config::Config, db, email::Mailer, storage::Storage,
    thetvdb::TheTvdbClient,
};

/// Cumulative background-work counters, for `BACKEND_PROFILE`. Lets the profiler show
/// enrich throughput and how much wall-clock the mirror's catalog writes cost —
/// separately from the TheTVDB API stats on the client. Cheap relaxed atomics.
#[derive(Default)]
pub struct SyncProfile {
    pub enriched: AtomicU64,  // series/movies/episodes fully enriched
    pub db_writes: AtomicU64, // catalog upsert statements (episodes, translations)
    pub db_us: AtomicU64,     // time spent in those upserts
}

impl SyncProfile {
    /// `(enriched, db_writes, db_us)` — cumulative.
    pub fn snapshot(&self) -> (u64, u64, u64) {
        (
            self.enriched.load(Ordering::Relaxed),
            self.db_writes.load(Ordering::Relaxed),
            self.db_us.load(Ordering::Relaxed),
        )
    }

    /// Record one catalog upsert and how long it took.
    pub fn record_write(&self, elapsed: std::time::Duration) {
        self.db_writes.fetch_add(1, Ordering::Relaxed);
        self.db_us.fetch_add(elapsed.as_micros() as u64, Ordering::Relaxed);
    }
}

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub tvdb: Arc<TheTvdbClient>,
    /// `None` when S3 is not configured. Object storage holds user-uploaded
    /// avatars & covers only (TheTVDB artwork is served straight from its CDN).
    pub storage: Option<Arc<Storage>>,
    pub config: Arc<Config>,
    /// Signalled whenever work is added to `catalog.fetch_queue`, so the
    /// enrichment worker drains immediately instead of waiting for its heartbeat.
    pub enrich_notify: Arc<Notify>,
    /// Outgoing email (password reset, invitations); log-only when SMTP is unset.
    pub mailer: Arc<Mailer>,
    /// In-memory throttle for auth endpoints (login/register/forgot/reset).
    pub auth_limiter: Arc<RateLimiter>,
    /// Per-user throttle for expensive read endpoints (search/discover/filter).
    pub read_limiter: Arc<RateLimiter>,
    /// Cumulative background-work counters (enrich/DB), surfaced by `BACKEND_PROFILE`.
    pub profile: Arc<SyncProfile>,
}

impl AppState {
    /// Connect to Postgres (running migrations), build the TheTVDB client and
    /// optional object storage. Shared by the server and the import CLI.
    pub async fn bootstrap(config: Config) -> anyhow::Result<AppState> {
        let db = db::connect_and_migrate(&config.database_url).await?;
        tracing::info!("migrations applied");

        let tvdb = Arc::new(TheTvdbClient::new(
            config.thetvdb_base_url.clone(),
            config.thetvdb_api_key.clone(),
            config.thetvdb_max_rps,
            config.backend_profile,
        ));

        let storage = Storage::from_config(&config).map(Arc::new);
        match &storage {
            Some(_) => tracing::info!("object storage enabled (bucket {})", config.s3_bucket),
            None => tracing::warn!("object storage disabled (no S3 creds)"),
        }

        let mailer = Arc::new(Mailer::from_config(config.smtp.as_ref()));

        Ok(AppState {
            db,
            tvdb,
            storage,
            config: Arc::new(config),
            enrich_notify: Arc::new(Notify::new()),
            mailer,
            auth_limiter: Arc::new(RateLimiter::new()),
            read_limiter: Arc::new(RateLimiter::new()),
            profile: Arc::new(SyncProfile::default()),
        })
    }
}
