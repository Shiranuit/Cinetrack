//! Tiny in-memory sliding-window rate limiter (single instance). Not distributed,
//! but adequate for one backend behind Caddy — it blunts brute-force and scripted
//! abuse on the auth endpoints. Keys are arbitrary strings, e.g. "login-ip:1.2.3.4"
//! or "login-acct:someone@example.com".

use std::{
    collections::HashMap,
    sync::Mutex,
    time::{Duration, Instant},
};

#[derive(Default)]
pub struct RateLimiter {
    hits: Mutex<HashMap<String, Vec<Instant>>>,
}

impl RateLimiter {
    pub fn new() -> Self {
        Self::default()
    }

    /// Record an attempt for `key`. Returns `true` if it's within `max` attempts
    /// over the trailing `window` (allowed), `false` if the limit is exceeded.
    pub fn check(&self, key: &str, max: usize, window: Duration) -> bool {
        let now = Instant::now();
        let mut map = self.hits.lock().unwrap();
        // Opportunistic global cleanup so the map can't grow without bound.
        if map.len() > 10_000 {
            map.retain(|_, v| v.iter().any(|&t| now.duration_since(t) < window));
        }
        let entry = map.entry(key.to_string()).or_default();
        entry.retain(|&t| now.duration_since(t) < window);
        if entry.len() >= max {
            false
        } else {
            entry.push(now);
            true
        }
    }

    /// Forget a key (e.g. after a successful login, so a good user isn't penalized
    /// by earlier failed attempts).
    pub fn reset(&self, key: &str) {
        self.hits.lock().unwrap().remove(key);
    }
}
