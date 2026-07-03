//! Catalog search. Behaviour depends on `CATALOG_MODE`:
//! - `proxy`  → passthrough to TheTVDB `/search`.
//! - `mirror` → local trigram search over the mirror only (no outbound calls).
//! - `hybrid` → local first; if results are thin, augment with TheTVDB and cache
//!   those hits so the mirror self-heals.
//!
//! Local search matches the base name, every alias (all languages) and the
//! stored translations, ranked by pg_trgm `word_similarity`.

use std::collections::HashSet;

use serde_json::Value;
use sqlx::{Postgres, QueryBuilder};

use crate::{catalog::as_i32, config::CatalogMode, error::AppResult, state::AppState};

/// How many local hits are "enough" before hybrid mode bothers TheTVDB.
const MIN_LOCAL: usize = 8;
const LOCAL_LIMIT: i64 = 50;

#[derive(serde::Serialize)]
pub struct SearchResult {
    pub tvdb_id: Option<i64>,
    pub kind: Option<String>, // "series" | "movie" | "person" | ...
    pub name: Option<String>, // translated to the caller's preferred language when available
    pub year: Option<i32>,
    pub image_url: Option<String>,
    pub overview: Option<String>,
}

/// Search the catalog. `langs` is the caller's language preference order (used
/// only to pick the display name; matching spans all languages).
pub async fn search(state: &AppState, query: &str, kind: Option<&str>, langs: &[String]) -> AppResult<Vec<SearchResult>> {
    let mode = state.config.catalog_mode;

    // Proxy: pure passthrough.
    if !mode.local_search() {
        return search_remote(state, query, kind, langs).await;
    }

    let mut local = search_local(state, query, kind, langs, LOCAL_LIMIT).await?;

    // Mirror: local only, never call out.
    if mode == CatalogMode::Mirror {
        return Ok(local);
    }

    // Hybrid: only reach for TheTVDB when the mirror is thin, and cache what we
    // get so the same search is served locally next time.
    if local.len() >= MIN_LOCAL {
        return Ok(local);
    }
    let seen: HashSet<i64> = local.iter().filter_map(|r| r.tvdb_id).collect();
    match search_remote(state, query, kind, langs).await {
        Ok(remote) => {
            for r in remote {
                if r.tvdb_id.is_none_or(|id| !seen.contains(&id)) {
                    local.push(r);
                }
            }
            Ok(local)
        }
        // TheTVDB unreachable → still serve whatever the mirror had.
        Err(e) => {
            tracing::warn!("hybrid search: remote unavailable, serving local only: {e}");
            Ok(local)
        }
    }
}

/// Passthrough to TheTVDB `/search`, mapped to `SearchResult`. Every series/movie
/// hit is also stored as a stub so the mirror builds toward full-local operation.
async fn search_remote(state: &AppState, query: &str, kind: Option<&str>, langs: &[String]) -> AppResult<Vec<SearchResult>> {
    let data = state.tvdb.search(query, kind).await?;
    let raw = data.as_array().cloned().unwrap_or_default();
    let mut out = Vec::with_capacity(raw.len());
    for r in &raw {
        let sr = map_result(r, langs);
        if let (Some(id), Some(table)) = (sr.tvdb_id, stub_table(sr.kind.as_deref())) {
            // Best-effort: a caching failure must not fail the search.
            let _ = super::store_stub(
                state,
                table,
                id,
                r["name"].as_str(),
                r["image_url"].as_str(),
                sr.year,
                r["primary_language"].as_str(),
                &super::alias_names(r),
            )
            .await;
        }
        out.push(sr);
    }
    Ok(out)
}

fn stub_table(kind: Option<&str>) -> Option<&'static str> {
    match kind {
        Some("series") => Some("catalog.series"),
        Some("movie") => Some("catalog.movie"),
        _ => None, // don't mirror persons/companies here
    }
}

/// Local, ranked, alias-aware search over the mirror.
pub async fn search_local(
    state: &AppState,
    query: &str,
    kind: Option<&str>,
    langs: &[String],
    limit: i64,
) -> AppResult<Vec<SearchResult>> {
    let mut out = Vec::new();
    let want_series = matches!(kind, None | Some("series") | Some("anime"));
    let want_movie = matches!(kind, None | Some("movie"));
    let anime_only = kind == Some("anime");

    if want_series {
        out.extend(search_table(state, "catalog.series", "series", query, langs, anime_only, limit).await?);
    }
    if want_movie {
        out.extend(search_table(state, "catalog.movie", "movie", query, langs, false, limit).await?);
    }
    Ok(out)
}

async fn search_table(
    state: &AppState,
    table: &str,
    etype: &str,
    query: &str,
    langs: &[String],
    anime_only: bool,
    limit: i64,
) -> AppResult<Vec<SearchResult>> {
    let like = format!("%{}%", escape_like(query));
    let langs = langs.to_vec();

    let mut qb: QueryBuilder<Postgres> = QueryBuilder::new("SELECT x.id, COALESCE((SELECT tr.name FROM catalog.translation tr WHERE tr.entity_type = ");
    qb.push_bind(etype);
    qb.push(" AND tr.entity_id = x.id AND tr.name IS NOT NULL AND tr.language = ANY(");
    qb.push_bind(langs.clone());
    qb.push(") ORDER BY array_position(");
    qb.push_bind(langs.clone());
    qb.push(", tr.language) LIMIT 1), x.name) AS name, x.year, x.image_url, x.overview FROM ");
    qb.push(table);
    // Match on: exact substring (ILIKE, covers short queries) OR fuzzy trigram
    // word-similarity (`<%`, catches punctuation/spelling drift like
    // "Dr STONE" vs "Dr.STONE") — both are GIN-trigram indexable — OR a
    // translation name in any language.
    qb.push(" x WHERE NOT x.deleted AND (x.search_text ILIKE ");
    qb.push_bind(like.clone());
    qb.push(" OR ");
    qb.push_bind(query.to_string());
    qb.push(" <% x.search_text OR EXISTS (SELECT 1 FROM catalog.translation t WHERE t.entity_type = ");
    qb.push_bind(etype);
    qb.push(" AND t.entity_id = x.id AND t.name ILIKE ");
    qb.push_bind(like.clone());
    qb.push("))");
    if anime_only {
        qb.push(" AND x.original_language IN ('jpn','ja')");
    }
    // Rank by trigram word-similarity of the query against the searchable doc,
    // taking the best of the base/alias text and any translation name.
    qb.push(" ORDER BY GREATEST(word_similarity(");
    qb.push_bind(query.to_string());
    qb.push(", x.search_text), COALESCE((SELECT max(word_similarity(");
    qb.push_bind(query.to_string());
    qb.push(", t.name)) FROM catalog.translation t WHERE t.entity_type = ");
    qb.push_bind(etype);
    qb.push(" AND t.entity_id = x.id AND t.name IS NOT NULL), 0)) DESC, x.score DESC NULLS LAST, x.name LIMIT ");
    qb.push_bind(limit);

    let rows = qb
        .build_query_as::<(i64, Option<String>, Option<i32>, Option<String>, Option<String>)>()
        .fetch_all(&state.db)
        .await?;

    let kind = if table.ends_with("movie") { "movie" } else { "series" };
    Ok(rows
        .into_iter()
        .map(|(id, name, year, image_url, overview)| SearchResult {
            tvdb_id: Some(id),
            kind: Some(kind.to_string()),
            name,
            year,
            image_url,
            overview,
        })
        .collect())
}

/// Escape LIKE/ILIKE wildcards so a query is matched literally.
fn escape_like(s: &str) -> String {
    s.replace('\\', "\\\\").replace('%', "\\%").replace('_', "\\_")
}

pub(crate) fn map_result(r: &Value, langs: &[String]) -> SearchResult {
    // TheTVDB search results carry `translations`/`overviews` maps keyed by language.
    let translations = &r["translations"];
    let overviews = &r["overviews"];
    let pick = |m: &Value| -> Option<String> {
        langs
            .iter()
            .find_map(|l| m[l].as_str().map(str::to_string))
    };

    SearchResult {
        tvdb_id: r["tvdb_id"].as_str().and_then(|s| s.parse().ok()),
        kind: r["type"].as_str().map(str::to_string),
        name: pick(translations).or_else(|| r["name"].as_str().map(str::to_string)),
        year: as_i32(&r["year"]),
        image_url: r["image_url"].as_str().map(str::to_string),
        overview: pick(overviews).or_else(|| r["overview"].as_str().map(str::to_string)),
    }
}
