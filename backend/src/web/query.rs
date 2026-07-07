//! Shared query-string extractors for the HTTP layer.

use serde::Deserialize;

#[derive(Debug, Deserialize)]
pub struct LangQuery {
    pub lang: Option<String>,
}

impl LangQuery {
    /// Resolve the effective language for a request:
    /// - absent            → `Some("eng")` (English by default)
    /// - `lang=original`   → `None` (serve TheTVDB's base record untranslated)
    /// - `lang=xxx`        → `Some("xxx")`
    pub fn resolve(&self) -> Option<String> {
        match self.lang.as_deref() {
            None => Some("eng".to_string()),
            Some("") | Some("original") => None,
            Some(l) => Some(l.to_string()),
        }
    }
}

/// Preferred language priority list, comma-separated (e.g. `?langs=fra,eng`).
#[derive(Debug, Deserialize)]
pub struct LangsQuery {
    pub langs: Option<String>,
}

impl LangsQuery {
    /// Ordered language codes; defaults to `["eng"]`.
    pub fn list(&self) -> Vec<String> {
        let v: Vec<String> = self
            .langs
            .as_deref()
            .unwrap_or("eng")
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        if v.is_empty() { vec!["eng".to_string()] } else { v }
    }
}

/// Detail-page language selection: prefer the ordered `langs` list; fall back to
/// the legacy single `lang` (older app builds), preserving `lang=original`/empty as
/// "no translation". Returns the preference list to resolve name/overview against
/// (empty means serve the untranslated base record).
#[derive(Debug, Deserialize)]
pub struct DetailLangQuery {
    pub lang: Option<String>,
    pub langs: Option<String>,
}

impl DetailLangQuery {
    pub fn list(&self) -> Vec<String> {
        if self.langs.is_some() {
            return LangsQuery { langs: self.langs.clone() }.list();
        }
        match self.lang.as_deref() {
            Some("") | Some("original") => vec![],
            Some(l) => vec![l.to_string()],
            None => vec!["eng".to_string()],
        }
    }
}

/// Parse a comma-separated list of integer ids from a query param, silently
/// dropping blanks and non-numeric entries (e.g. `"1, 2 ,x,"` → `[1, 2]`).
pub fn csv_ids(raw: Option<&str>) -> Vec<i64> {
    raw.unwrap_or("")
        .split(',')
        .filter_map(|x| x.trim().parse::<i64>().ok())
        .collect()
}

/// Parse a comma-separated list of (trimmed, non-empty) strings.
pub fn csv_strings(raw: Option<&str>) -> Vec<String> {
    raw.unwrap_or("")
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .collect()
}
