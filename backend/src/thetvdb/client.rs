use std::{
    collections::{HashMap, VecDeque},
    sync::{Arc, Mutex as StdMutex},
    time::{Duration, Instant},
};

use reqwest::Client;
use serde_json::Value;
use tokio::sync::{OnceCell, RwLock};

use crate::error::AppError;

/// TheTVDB v4 tokens are valid for 1 month and there is no refresh endpoint — we
/// re-login well before expiry.
const TOKEN_MAX_AGE: Duration = Duration::from_secs(25 * 24 * 3600);

/// TheTVDB's documented limit is ~40 req/s. We pace globally a touch under that to
/// leave headroom for other clients / bursts.
const MAX_REQUESTS_PER_SEC: u32 = 35;
/// How many times to retry a request that is rate-limited (429) or hits a transient
/// 5xx before giving up.
const MAX_RETRIES: u32 = 4;

struct Token {
    value: String,
    fetched_at: Instant,
}

/// A cloneable fetch outcome so single-flight can hand the same result to every
/// coalesced caller. `AppError` isn't `Clone`, so we keep just what we need and
/// rebuild the error (preserving `NotFound`, which the read-through relies on).
#[derive(Clone)]
enum FetchOutcome {
    Ok(Value),
    NotFound,
    Err(String),
}

impl FetchOutcome {
    fn into_result(self) -> Result<Value, AppError> {
        match self {
            FetchOutcome::Ok(v) => Ok(v),
            FetchOutcome::NotFound => Err(AppError::NotFound),
            FetchOutcome::Err(m) => Err(AppError::TheTvdb(m)),
        }
    }
}

/// Request priority. **All** requests share the one global rate limit, but the
/// waiting queue is split: interactive (`High`) requests are always served before
/// background mirror work (`Low` — enrichment/crawl/sync). So a user's search
/// never waits behind thousands of queued background fetches.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Priority {
    High,
    Low,
}

tokio::task_local! {
    static PRIORITY: Priority;
}

/// Run `fut` (and any TheTVDB calls it awaits **in the same task**) at
/// `priority`. Background jobs wrap their work in `Priority::Low`. Task-locals
/// don't cross `spawn`, so a job that spawns child fetch tasks must scope each
/// child. Anything not wrapped defaults to `High` (interactive).
pub async fn with_priority<F: std::future::Future>(priority: Priority, fut: F) -> F::Output {
    PRIORITY.scope(priority, fut).await
}

fn current_priority() -> Priority {
    PRIORITY.try_with(|p| *p).unwrap_or(Priority::High)
}

/// Global request pacer. A single dispatcher releases one waiter every `interval`
/// (≤ target rps), always draining the High queue before the Low queue — so
/// interactive latency stays ~one slot even while a full-catalog crawl runs.
/// Construct within a Tokio runtime (it spawns the dispatcher).
struct RateLimiter {
    shared: Arc<LimiterShared>,
}

#[derive(Default)]
struct LimiterState {
    high: VecDeque<tokio::sync::oneshot::Sender<()>>,
    low: VecDeque<tokio::sync::oneshot::Sender<()>>,
}

struct LimiterShared {
    state: StdMutex<LimiterState>,
}

impl RateLimiter {
    fn new(per_sec: u32) -> Self {
        let interval = Duration::from_secs_f64(1.0 / per_sec.max(1) as f64);
        let shared = Arc::new(LimiterShared { state: StdMutex::new(LimiterState::default()) });

        // Dispatcher: one release per interval, High first. A Weak ref lets it
        // stop once the client is dropped (so tests/CLIs don't leak the task).
        let weak = Arc::downgrade(&shared);
        tokio::spawn(async move {
            let mut ticker = tokio::time::interval(interval);
            ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            loop {
                ticker.tick().await;
                let Some(shared) = weak.upgrade() else { break };
                let waiter = {
                    let mut st = shared.state.lock().unwrap();
                    st.high.pop_front().or_else(|| st.low.pop_front())
                };
                if let Some(tx) = waiter {
                    let _ = tx.send(());
                }
            }
        });

        Self { shared }
    }

    /// Wait for a paced slot at the current task's priority (default `High`).
    async fn acquire(&self) {
        let (tx, rx) = tokio::sync::oneshot::channel();
        {
            let mut st = self.shared.state.lock().unwrap();
            match current_priority() {
                Priority::High => st.high.push_back(tx),
                Priority::Low => st.low.push_back(tx),
            }
        }
        let _ = rx.await;
    }
}

/// Thin client for the TheTVDB v4 API. Handles login + JWT caching. All GETs
/// return the `data` field of the envelope as raw JSON.
///
/// Every GET goes through a **global rate limiter** (≤ `MAX_REQUESTS_PER_SEC`),
/// **retries 429/5xx** honoring `Retry-After`, and is **de-duplicated**: identical
/// concurrent GETs (same path+params) coalesce into a single upstream request via
/// single-flight — so two users importing the same series only hit TheTVDB once.
pub struct TheTvdbClient {
    http: Client,
    base_url: String,
    api_key: String,
    token: RwLock<Option<Token>>,
    limiter: RateLimiter,
    inflight: StdMutex<HashMap<String, Arc<OnceCell<FetchOutcome>>>>,
}

impl TheTvdbClient {
    pub fn new(base_url: String, api_key: String, max_rps: u32) -> Self {
        Self {
            http: Client::new(),
            base_url,
            api_key,
            token: RwLock::new(None),
            limiter: RateLimiter::new(if max_rps > 0 { max_rps } else { MAX_REQUESTS_PER_SEC }),
            inflight: StdMutex::new(HashMap::new()),
        }
    }

    async fn login(&self) -> Result<String, AppError> {
        let url = format!("{}/login", self.base_url);
        let resp = self
            .http
            .post(&url)
            .json(&serde_json::json!({ "apikey": self.api_key }))
            .send()
            .await
            .map_err(|e| AppError::TheTvdb(format!("login request failed: {e}")))?;

        if !resp.status().is_success() {
            return Err(AppError::TheTvdb(format!("login failed: HTTP {}", resp.status())));
        }
        let body: Value = resp
            .json()
            .await
            .map_err(|e| AppError::TheTvdb(format!("login decode failed: {e}")))?;
        body["data"]["token"]
            .as_str()
            .map(str::to_owned)
            .ok_or_else(|| AppError::TheTvdb("no token in login response".into()))
    }

    async fn token(&self) -> Result<String, AppError> {
        if let Some(tok) = self.token.read().await.as_ref() {
            if tok.fetched_at.elapsed() < TOKEN_MAX_AGE {
                return Ok(tok.value.clone());
            }
        }
        let value = self.login().await?;
        *self.token.write().await = Some(Token {
            value: value.clone(),
            fetched_at: Instant::now(),
        });
        Ok(value)
    }

    /// GET `{base}{path}` with bearer auth; returns the `data` field of the response.
    pub async fn get(&self, path: &str) -> Result<Value, AppError> {
        self.get_query(path, &[]).await
    }

    /// Like `get`, but with URL-encoded query parameters. Rate-limited, retried on
    /// 429/5xx, and de-duplicated via single-flight (identical concurrent GETs share
    /// one upstream request).
    pub async fn get_query(&self, path: &str, params: &[(&str, &str)]) -> Result<Value, AppError> {
        let key = request_key(path, params);

        // Join an in-flight identical request if one exists, else become its leader.
        let cell = {
            let mut inflight = self.inflight.lock().unwrap();
            inflight.entry(key.clone()).or_insert_with(|| Arc::new(OnceCell::new())).clone()
        };
        let outcome = cell.get_or_init(|| self.fetch_paced(path, params)).await.clone();
        // Drop the slot so a later (post-completion) request re-fetches fresh.
        self.inflight.lock().unwrap().remove(&key);

        outcome.into_result()
    }

    /// The actual paced + retrying fetch (run once per single-flight group).
    async fn fetch_paced(&self, path: &str, params: &[(&str, &str)]) -> FetchOutcome {
        let token = match self.token().await {
            Ok(t) => t,
            Err(e) => return outcome_from(e),
        };
        let url = format!("{}{}", self.base_url, path);

        for attempt in 0..=MAX_RETRIES {
            self.limiter.acquire().await; // pace every attempt (retries included)

            let resp = self.http.get(&url).query(params).bearer_auth(&token).send().await;
            let resp = match resp {
                Ok(r) => r,
                Err(e) => return FetchOutcome::Err(format!("GET {path} failed: {e}")),
            };
            let status = resp.status();

            // 429 (or a transient 5xx): honor Retry-After, back off, and retry.
            if status == reqwest::StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
                if attempt == MAX_RETRIES {
                    return FetchOutcome::Err(format!("GET {path} -> HTTP {status} after {MAX_RETRIES} retries"));
                }
                let wait = retry_after(&resp).unwrap_or_else(|| backoff(attempt));
                tracing::warn!("TheTVDB {status} on {path}; retrying in {:.1}s", wait.as_secs_f64());
                tokio::time::sleep(wait).await;
                continue;
            }
            if status == reqwest::StatusCode::NOT_FOUND {
                return FetchOutcome::NotFound;
            }
            if !status.is_success() {
                return FetchOutcome::Err(format!("GET {path} -> HTTP {status}"));
            }
            return match resp.json::<Value>().await {
                Ok(body) => FetchOutcome::Ok(body["data"].clone()),
                Err(e) => FetchOutcome::Err(format!("GET {path} decode failed: {e}")),
            };
        }
        unreachable!("retry loop always returns")
    }

    pub async fn series_extended(&self, id: i64) -> Result<Value, AppError> {
        self.get(&format!("/series/{id}/extended")).await
    }

    /// Extended series record **with all name/overview translations bundled**
    /// (`?meta=translations`) — one call gives us every language for the mirror.
    pub async fn series_extended_translated(&self, id: i64) -> Result<Value, AppError> {
        self.get_query(&format!("/series/{id}/extended"), &[("meta", "translations")]).await
    }

    pub async fn movie_extended(&self, id: i64) -> Result<Value, AppError> {
        self.get(&format!("/movies/{id}/extended")).await
    }

    /// Extended movie record with all translations bundled (`?meta=translations`).
    pub async fn movie_extended_translated(&self, id: i64) -> Result<Value, AppError> {
        self.get_query(&format!("/movies/{id}/extended"), &[("meta", "translations")]).await
    }

    pub async fn episode(&self, id: i64) -> Result<Value, AppError> {
        self.get(&format!("/episodes/{id}")).await
    }

    pub async fn season_extended(&self, id: i64) -> Result<Value, AppError> {
        self.get(&format!("/seasons/{id}/extended")).await
    }

    pub async fn artwork_extended(&self, id: i64) -> Result<Value, AppError> {
        self.get(&format!("/artwork/{id}/extended")).await
    }

    /// Translation for an entity in a given language. `kind` is the URL segment
    /// (`series`, `movies`, `episodes`, `seasons`). Returns `NotFound` (HTTP 404)
    /// when no translation exists for that language.
    pub async fn translation(&self, kind: &str, id: i64, lang: &str) -> Result<Value, AppError> {
        self.get(&format!("/{kind}/{id}/translations/{lang}")).await
    }

    /// One page of a series' episodes for a season-type (e.g. `default`), optionally
    /// translated to `lang`. Returns the `data` object: `{ series, episodes: [...] }`.
    pub async fn series_episodes(
        &self,
        id: i64,
        season_type: &str,
        lang: Option<&str>,
        page: u32,
    ) -> Result<Value, AppError> {
        let page = page.to_string();
        let path = match lang {
            Some(l) => format!("/series/{id}/episodes/{season_type}/{l}"),
            None => format!("/series/{id}/episodes/{season_type}"),
        };
        self.get_query(&path, &[("page", &page)]).await
    }

    /// One page of the change feed since `since` (unix ts) for an entity `kind`
    /// (`series`, `movies`, `episodes`, `seasons`, ...). Returns the `data` array
    /// of change records.
    pub async fn updates(&self, since: i64, kind: &str, page: u32) -> Result<Value, AppError> {
        let since = since.to_string();
        let page = page.to_string();
        self.get_query("/updates", &[("since", &since), ("type", kind), ("page", &page)]).await
    }

    /// Series filter/browse (Discover). Pass params like `sort=score`, `genre=…`.
    pub async fn series_filter(&self, params: &[(&str, &str)]) -> Result<Value, AppError> {
        self.get_query("/series/filter", params).await
    }

    /// Movies filter/browse (Discover).
    pub async fn movies_filter(&self, params: &[(&str, &str)]) -> Result<Value, AppError> {
        self.get_query("/movies/filter", params).await
    }

    /// One page of the full series list (basic records) — enumeration for the seed
    /// crawl. Pages are 0-indexed; an empty page marks the end.
    pub async fn series_page(&self, page: u32) -> Result<Value, AppError> {
        self.get_query("/series", &[("page", &page.to_string())]).await
    }

    /// One page of the full movies list (basic records) for the seed crawl.
    pub async fn movies_page(&self, page: u32) -> Result<Value, AppError> {
        self.get_query("/movies", &[("page", &page.to_string())]).await
    }

    /// All genres.
    pub async fn genres(&self) -> Result<Value, AppError> {
        self.get("/genres").await
    }

    /// Full-text search. `kind` optionally filters by type (`series`, `movie`, ...).
    pub async fn search(&self, query: &str, kind: Option<&str>) -> Result<Value, AppError> {
        let mut params = vec![("query", query)];
        if let Some(k) = kind {
            params.push(("type", k));
        }
        self.get_query("/search", &params).await
    }
}

/// Stable single-flight key for a request (path + its query params).
fn request_key(path: &str, params: &[(&str, &str)]) -> String {
    let mut key = String::from(path);
    for (k, v) in params {
        key.push('\u{1f}'); // unit separator — safe against values containing '&'/'='
        key.push_str(k);
        key.push('=');
        key.push_str(v);
    }
    key
}

/// Parse a `Retry-After` header (delta-seconds form) into a duration.
fn retry_after(resp: &reqwest::Response) -> Option<Duration> {
    resp.headers()
        .get(reqwest::header::RETRY_AFTER)?
        .to_str()
        .ok()?
        .trim()
        .parse::<u64>()
        .ok()
        .map(Duration::from_secs)
}

/// Exponential backoff for retry `attempt` (0-based): 0.5s, 1s, 2s, 4s …
fn backoff(attempt: u32) -> Duration {
    Duration::from_millis(500 * 2u64.pow(attempt))
}

fn outcome_from(e: AppError) -> FetchOutcome {
    match e {
        AppError::NotFound => FetchOutcome::NotFound,
        other => FetchOutcome::Err(other.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;

    /// A High-priority acquire arriving after a flood of Low ones must be served
    /// almost immediately — not after the whole backlog drains.
    #[tokio::test]
    async fn high_priority_jumps_the_queue() {
        let limiter = Arc::new(RateLimiter::new(1000)); // ~1ms/slot
        let order = Arc::new(AtomicUsize::new(0));

        // Flood the Low lane with 100 background waiters.
        for _ in 0..100 {
            let l = limiter.clone();
            let o = order.clone();
            tokio::spawn(with_priority(Priority::Low, async move {
                l.acquire().await;
                o.fetch_add(1, Ordering::SeqCst);
            }));
        }
        // Let them enqueue (and a few drain).
        tokio::time::sleep(Duration::from_millis(5)).await;

        // An interactive request arrives late.
        let l = limiter.clone();
        let o = order.clone();
        let served_at = tokio::spawn(with_priority(Priority::High, async move {
            l.acquire().await;
            o.fetch_add(1, Ordering::SeqCst) // returns the count BEFORE increment
        }))
        .await
        .unwrap();

        // It jumped the ~95 still-queued Low requests instead of waiting behind them.
        assert!(served_at < 30, "high served at position {served_at}, expected near the front");
    }

    /// With no High waiters, Low requests still get served (no starvation of the
    /// only lane in use).
    #[tokio::test]
    async fn low_priority_drains_when_alone() {
        let limiter = Arc::new(RateLimiter::new(1000));
        let mut handles = Vec::new();
        for _ in 0..10 {
            let l = limiter.clone();
            handles.push(tokio::spawn(with_priority(Priority::Low, async move { l.acquire().await })));
        }
        for h in handles {
            h.await.unwrap();
        }
    }
}
