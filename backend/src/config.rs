use std::env;

/// How the catalog sources its data from TheTVDB. This is a global read-through
/// policy — it governs EVERY catalog request (series/movie/episodes/seasons/
/// artwork/search), not just search.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CatalogMode {
    /// Serve only from the local mirror; never call TheTVDB. On a cache miss the
    /// request 404s. Zero outbound dependency (the /updates worker fills the DB).
    Mirror,
    /// Pure read-through: fetch from TheTVDB on miss/stale; search hits TheTVDB.
    Proxy,
    /// Read-through like Proxy for detail reads, but search consults the local
    /// mirror first and only falls back to TheTVDB when local results are thin
    /// (caching those hits so the mirror self-heals).
    Hybrid,
}

impl CatalogMode {
    fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "mirror" => Self::Mirror,
            "proxy" => Self::Proxy,
            _ => Self::Hybrid,
        }
    }

    /// May we call out to TheTVDB at all?
    pub fn allow_remote(self) -> bool {
        self != Self::Mirror
    }

    /// Should search consult the local mirror first (Mirror + Hybrid)?
    pub fn local_search(self) -> bool {
        self != Self::Proxy
    }
}

/// How much of TheTVDB the mirror tries to hold. Gates whether the seed crawl
/// runs and whether `/updates` inserts brand-new entities we've never seen.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MirrorScope {
    /// Only mirror entities we're asked about (reads/tracking); `/updates`
    /// reconciles those we already hold but does not pull in new ones.
    OnDemand,
    /// Mirror the whole catalog: seed-crawl everything and let `/updates` add new.
    Full,
}

impl MirrorScope {
    fn parse(s: &str) -> Self {
        match s.trim().to_ascii_lowercase().as_str() {
            "full" => Self::Full,
            _ => Self::OnDemand,
        }
    }
}

/// Runtime configuration, loaded from environment (see `.env.example`).
#[derive(Clone, Debug)]
pub struct Config {
    pub database_url: String,
    pub catalog_mode: CatalogMode,
    pub mirror_scope: MirrorScope,
    pub bind_addr: String,
    pub thetvdb_base_url: String,
    pub thetvdb_api_key: String,
    pub jwt_secret: String,
    /// Public URL clients reach the API at (used to build absolute media URLs).
    pub public_base_url: String,
    pub s3_endpoint: String,
    pub s3_region: String,
    pub s3_bucket: String,
    pub s3_access_key: String,
    pub s3_secret_key: String,
    /// If set, the server runs the /updates sync worker on this interval (seconds).
    pub sync_interval_secs: Option<u64>,
    /// Max outbound requests/sec to TheTVDB (global pacer). Undocumented upstream;
    /// tune empirically. Default 35.
    pub thetvdb_max_rps: u32,
    /// If set, the server runs the background enrichment worker on this interval
    /// (seconds) to drain the fetch queue. Unset = disabled (use `bin/mirror`).
    pub enrich_interval_secs: Option<u64>,
    /// Number of concurrent in-flight enrichment fetches (bounds queue drain
    /// parallelism; the rate pacer still caps total throughput). Default 8.
    pub enrich_concurrency: usize,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        fn req(key: &str) -> anyhow::Result<String> {
            env::var(key).map_err(|_| anyhow::anyhow!("missing required env var {key}"))
        }
        fn opt(key: &str, default: &str) -> String {
            env::var(key).unwrap_or_else(|_| default.to_string())
        }

        Ok(Self {
            database_url: req("DATABASE_URL")?,
            catalog_mode: CatalogMode::parse(&opt("CATALOG_MODE", "hybrid")),
            mirror_scope: MirrorScope::parse(&opt("MIRROR_SCOPE", "on-demand")),
            bind_addr: opt("BACKEND_BIND_ADDR", "0.0.0.0:8080"),
            thetvdb_base_url: opt("THETVDB_BASE_URL", "https://api4.thetvdb.com/v4"),
            thetvdb_api_key: req("THETVDB_API_KEY")?,
            jwt_secret: req("JWT_SECRET")?,
            public_base_url: opt("PUBLIC_BASE_URL", "http://localhost:8080"),
            s3_endpoint: opt("S3_ENDPOINT", ""),
            s3_region: opt("S3_REGION", "garage"),
            s3_bucket: opt("S3_BUCKET", "artwork"),
            s3_access_key: opt("S3_ACCESS_KEY", ""),
            s3_secret_key: opt("S3_SECRET_KEY", ""),
            sync_interval_secs: env::var("SYNC_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()),
            thetvdb_max_rps: env::var("THETVDB_MAX_RPS").ok().and_then(|v| v.parse().ok()).filter(|&n| n > 0).unwrap_or(35),
            enrich_interval_secs: env::var("ENRICH_INTERVAL_SECS").ok().and_then(|v| v.parse().ok()),
            enrich_concurrency: env::var("ENRICH_CONCURRENCY").ok().and_then(|v| v.parse().ok()).filter(|&n| n > 0).unwrap_or(8),
        })
    }
}
