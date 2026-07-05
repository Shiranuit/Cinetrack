//! Generic, per-entity translation read-through, shared by series/movie/episode/season.

use serde_json::Value;

use crate::{
    catalog::TTL,
    error::{AppError, AppResult},
    state::AppState,
};

pub struct Translation {
    pub name: Option<String>,
    pub overview: Option<String>,
}

/// Store all translations bundled in an `?meta=translations` extended record, in
/// one batched upsert. The bundle keys name & overview by language separately
/// (`translations.nameTranslations[]` / `.overviewTranslations[]`), so we merge
/// them per language. COALESCE keeps whichever side a given language provides.
pub async fn store_bundle(state: &AppState, entity_type: &str, id: i64, data: &Value) -> AppResult<()> {
    use std::collections::HashMap;
    let bundle = &data["translations"];
    let mut by_lang: HashMap<&str, (Option<&str>, Option<&str>)> = HashMap::new();
    for n in bundle["nameTranslations"].as_array().into_iter().flatten() {
        if let Some(lang) = n["language"].as_str() {
            by_lang.entry(lang).or_default().0 = n["name"].as_str().filter(|s| !s.is_empty());
        }
    }
    for o in bundle["overviewTranslations"].as_array().into_iter().flatten() {
        if let Some(lang) = o["language"].as_str() {
            by_lang.entry(lang).or_default().1 = o["overview"].as_str().filter(|s| !s.is_empty());
        }
    }
    if by_lang.is_empty() {
        return Ok(());
    }

    let langs: Vec<&str> = by_lang.keys().copied().collect();
    let names: Vec<Option<&str>> = langs.iter().map(|l| by_lang[l].0).collect();
    let overviews: Vec<Option<&str>> = langs.iter().map(|l| by_lang[l].1).collect();

    sqlx::query(
        "INSERT INTO catalog.translation (entity_type, entity_id, language, name, overview, last_synced_at) \
         SELECT $1, $2, l, n, o, now() FROM UNNEST($3::text[], $4::text[], $5::text[]) AS t(l, n, o) \
         ON CONFLICT (entity_type, entity_id, language) DO UPDATE SET \
           name = COALESCE(EXCLUDED.name, catalog.translation.name), \
           overview = COALESCE(EXCLUDED.overview, catalog.translation.overview), \
           last_synced_at = now()",
    )
    .bind(entity_type)
    .bind(id)
    .bind(&langs)
    .bind(&names)
    .bind(&overviews)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Map our `entity_type` to the TheTVDB URL segment.
fn url_kind(entity_type: &str) -> &'static str {
    match entity_type {
        "movie" => "movies",
        "episode" => "episodes",
        "season" => "seasons",
        _ => "series",
    }
}

/// Map our `entity_type` to its catalog table (for reading available languages).
fn table(entity_type: &str) -> &'static str {
    match entity_type {
        "movie" => "catalog.movie",
        "episode" => "catalog.episode",
        "season" => "catalog.season",
        _ => "catalog.series",
    }
}

/// Fetch (read-through) a single translation, returning `None` if TheTVDB has
/// no translation for that language.
async fn ensure(state: &AppState, entity_type: &str, id: i64, lang: &str) -> AppResult<Option<Translation>> {
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT last_synced_at > now() - interval '{TTL}' \
         FROM catalog.translation WHERE entity_type = $1 AND entity_id = $2 AND language = $3"
    ))
    .bind(entity_type)
    .bind(id)
    .bind(lang)
    .fetch_optional(&state.db)
    .await?;

    // Mirror mode never calls out; serve whatever translation is cached (if any).
    if fresh != Some(true) && state.config.catalog_mode.allow_remote() {
        match state.tvdb.translation(url_kind(entity_type), id, lang).await {
            Ok(data) => upsert(state, entity_type, id, lang, &data).await?,
            Err(AppError::NotFound) => {
                // Negative cache: record that TheTVDB has no translation for this
                // (entity, language) so we don't re-request it every TTL. Matters
                // most for per-episode lookups, where a show lacking a translation
                // in the user's language would otherwise refetch on every view.
                sqlx::query(
                    "INSERT INTO catalog.translation (entity_type, entity_id, language) \
                     VALUES ($1, $2, $3) \
                     ON CONFLICT (entity_type, entity_id, language) DO UPDATE SET last_synced_at = now()",
                )
                .bind(entity_type)
                .bind(id)
                .bind(lang)
                .execute(&state.db)
                .await?;
            }
            Err(e) => return Err(e),
        }
    }

    let row: Option<(Option<String>, Option<String>)> = sqlx::query_as(
        "SELECT name, overview FROM catalog.translation \
         WHERE entity_type = $1 AND entity_id = $2 AND language = $3",
    )
    .bind(entity_type)
    .bind(id)
    .bind(lang)
    .fetch_optional(&state.db)
    .await?;

    Ok(row.map(|(name, overview)| Translation { name, overview }))
}

async fn upsert(state: &AppState, entity_type: &str, id: i64, lang: &str, data: &Value) -> AppResult<()> {
    let name = data["name"].as_str();
    let overview = data["overview"].as_str();
    let is_alias = data["isAlias"].as_bool();
    let is_primary = data["isPrimary"].as_bool();

    sqlx::query(
        "INSERT INTO catalog.translation \
           (entity_type, entity_id, language, name, overview, is_alias, is_primary, raw, last_synced_at) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8, now()) \
         ON CONFLICT (entity_type, entity_id, language) DO UPDATE SET \
           name=EXCLUDED.name, overview=EXCLUDED.overview, is_alias=EXCLUDED.is_alias, \
           is_primary=EXCLUDED.is_primary, raw=EXCLUDED.raw, last_synced_at=now()",
    )
    .bind(entity_type)
    .bind(id)
    .bind(lang)
    .bind(name)
    .bind(overview)
    .bind(is_alias)
    .bind(is_primary)
    .bind(sqlx::types::Json(data))
    .execute(&state.db)
    .await?;

    Ok(())
}

/// Overlay the requested language's translation onto `name`/`overview` in place.
/// Returns `Some(lang)` when a translation exists (so callers can label the row),
/// or `None` when `lang` is `None` or no translation is available.
pub async fn apply(
    state: &AppState,
    entity_type: &str,
    id: i64,
    lang: Option<&str>,
    name: &mut Option<String>,
    overview: &mut Option<String>,
) -> AppResult<Option<String>> {
    let Some(lang) = lang else { return Ok(None) };
    let Some(t) = ensure(state, entity_type, id, lang).await? else { return Ok(None) };

    // Only label the row as translated when something was actually overlaid — a
    // negative-cache tombstone (name/overview NULL) counts as "no translation".
    let mut applied = false;
    if t.name.as_deref().is_some_and(|s| !s.is_empty()) {
        *name = t.name;
        applied = true;
    }
    if t.overview.as_deref().is_some_and(|s| !s.is_empty()) {
        *overview = t.overview;
        applied = true;
    }
    Ok(applied.then(|| lang.to_string()))
}

/// Upsert a single translation row (used when mirroring translations in bulk,
/// e.g. from the episodes-by-language endpoint). COALESCE keeps any existing
/// name/overview when the incoming value is NULL, so a partial fetch never wipes
/// a good translation.
pub async fn store_one(
    state: &AppState,
    entity_type: &str,
    id: i64,
    lang: &str,
    name: Option<&str>,
    overview: Option<&str>,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO catalog.translation (entity_type, entity_id, language, name, overview, last_synced_at) \
         VALUES ($1, $2, $3, $4, $5, now()) \
         ON CONFLICT (entity_type, entity_id, language) DO UPDATE SET \
           name = COALESCE(EXCLUDED.name, catalog.translation.name), \
           overview = COALESCE(EXCLUDED.overview, catalog.translation.overview), \
           last_synced_at = now()",
    )
    .bind(entity_type)
    .bind(id)
    .bind(lang)
    .bind(name)
    .bind(overview)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Warm the translation cache for many entities of one type in `lang`, with
/// bounded concurrency. Best-effort: individual failures are ignored so one bad
/// or missing translation never fails the batch. Used to overlay per-episode
/// translations without N sequential round-trips.
pub async fn prefetch(state: &AppState, entity_type: &str, ids: &[i64], lang: &str) {
    const CONCURRENCY: usize = 8;
    for chunk in ids.chunks(CONCURRENCY) {
        let mut set = tokio::task::JoinSet::new();
        for &id in chunk {
            let state = state.clone();
            let entity_type = entity_type.to_string();
            let lang = lang.to_string();
            set.spawn(async move {
                let _ = ensure(&state, &entity_type, id, &lang).await;
            });
        }
        while set.join_next().await.is_some() {}
    }
}

/// Languages for which TheTVDB has a name and/or overview, read from the cached
/// base record's `nameTranslations` / `overviewTranslations` lists.
pub async fn available_languages(state: &AppState, entity_type: &str, id: i64) -> AppResult<Vec<String>> {
    let raw: Option<Value> = sqlx::query_scalar(&format!(
        "SELECT raw FROM {} WHERE id = $1",
        table(entity_type)
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    let Some(raw) = raw else { return Ok(vec![]) };

    let mut langs: Vec<String> = ["nameTranslations", "overviewTranslations"]
        .iter()
        .filter_map(|k| raw[*k].as_array())
        .flatten()
        .filter_map(|v| v.as_str().map(str::to_owned))
        .collect();
    langs.sort();
    langs.dedup();
    Ok(langs)
}
