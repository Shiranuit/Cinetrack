use std::sync::Arc;

use sqlx::PgPool;
use tokio::sync::Notify;

use crate::{config::Config, db, storage::Storage, thetvdb::TheTvdbClient};

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
        ));

        let storage = Storage::from_config(&config).map(Arc::new);
        match &storage {
            Some(_) => tracing::info!("object storage enabled (bucket {})", config.s3_bucket),
            None => tracing::warn!("object storage disabled (no S3 creds)"),
        }

        Ok(AppState {
            db,
            tvdb,
            storage,
            config: Arc::new(config),
            enrich_notify: Arc::new(Notify::new()),
        })
    }
}
