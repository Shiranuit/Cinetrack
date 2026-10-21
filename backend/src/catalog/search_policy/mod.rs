//! Discover guard persisted by migration 0048, folded by 0049. Startup
//! only loads the snapshot; request-time decisions are in-memory lookups.

use std::{collections::HashMap, time::Instant};

use sqlx::PgPool;

#[cfg(test)]
mod tests;

/// Initial cutoff, calibrated against the local catalog: require both a large
/// absolute candidate set and a substantial share of the language's catalog.
const MIN_TITLES: i64 = 5_000;
const MIN_FRACTION: f64 = 0.02;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SearchMode {
    Full,
    Exact,
}

impl SearchMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Full => "full",
            Self::Exact => "exact",
        }
    }
}

#[derive(Debug, sqlx::FromRow)]
struct Frequency {
    kind: String,
    language: String,
    term: String,
    matches: i64,
    titles: i64,
}

#[derive(Debug, Default)]
pub struct SearchBaseline {
    // kind -> language -> common term -> distinct-title count. Only broad terms
    // survive the offline aggregation, keeping this cache small.
    common: HashMap<String, HashMap<String, HashMap<String, i64>>>,
}

impl SearchBaseline {
    /// Loads the persisted snapshot after migrations. This never scans titles or
    /// recomputes frequencies, even when the saved snapshot is empty.
    pub async fn load(db: &PgPool) -> Result<Self, sqlx::Error> {
        let started = Instant::now();
        let rows = sqlx::query_as::<_, Frequency>(
            "SELECT kind, language, term, matches, titles FROM catalog.search_word_baseline",
        )
        .fetch_all(db)
        .await?;
        let terms = rows.len();
        let baseline = Self::from_frequencies(rows);
        tracing::info!(
            terms,
            elapsed_ms = started.elapsed().as_millis(),
            min_titles = MIN_TITLES,
            min_fraction = MIN_FRACTION,
            "persisted search baseline loaded"
        );
        Ok(baseline)
    }

    fn from_frequencies(rows: Vec<Frequency>) -> Self {
        let mut baseline = Self::default();
        for row in rows {
            if row.matches >= MIN_TITLES && row.matches as f64 >= row.titles as f64 * MIN_FRACTION {
                baseline
                    .common
                    .entry(row.kind)
                    .or_default()
                    .entry(row.language)
                    .or_default()
                    .insert(row.term, row.matches);
            }
        }
        baseline
    }

    /// Input is already folded with catalog.fold_search_text by the query layer.
    pub fn mode(&self, query: Option<&str>, kind: &str, langs: &[String]) -> SearchMode {
        let Some(query) = query else {
            return SearchMode::Full;
        };
        let words = words(query);
        if words.len() != 1 {
            // Punctuation-only input is marked exact so the query layer can
            // return no matches without a wildcard-only catalog scan.
            return if words.is_empty() {
                SearchMode::Exact
            } else {
                SearchMode::Full
            };
        }
        let word = &words[0];
        // One/two-character substrings cannot narrow our trigram indexes. Exact
        // title lookup keeps It and Up discoverable without that scan.
        if word.chars().count() < 3 {
            return SearchMode::Exact;
        }
        let kind = if kind == "movie" { "movie" } else { "series" };
        let Some(languages) = self.common.get(kind) else {
            return SearchMode::Full;
        };
        if std::iter::once("*")
            .chain(langs.iter().map(String::as_str))
            .any(|lang| {
                languages
                    .get(lang)
                    .is_some_and(|terms| terms.contains_key(word))
            })
        {
            SearchMode::Exact
        } else {
            SearchMode::Full
        }
    }
}

/// Shared query tokenization for frequency guards and flexible title matching.
pub(crate) fn words(query: &str) -> Vec<String> {
    query
        .to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|word| !word.is_empty())
        .map(str::to_owned)
        .collect()
}
