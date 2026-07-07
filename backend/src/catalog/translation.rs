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

    // Persist the raw bundle first (durable: routine base refresh leaves this column
    // alone), so any future change to how we derive display names / handle aliases can
    // re-run from local data instead of re-querying the whole of TheTVDB.
    if !bundle.is_null() && let Some(tbl) = raw_translations_table(entity_type) {
        sqlx::query(&format!("UPDATE {tbl} SET raw_translations = $2 WHERE id = $1"))
            .bind(id)
            .bind(sqlx::types::Json(bundle))
            .execute(&state.db)
            .await?;
    }

    let mut by_lang: HashMap<&str, (Option<&str>, Option<&str>)> = HashMap::new();
    for n in bundle["nameTranslations"].as_array().into_iter().flatten() {
        // TheTVDB mixes the real translated name with ALIASES in this array, tagged
        // `isAlias: true` (e.g. a romanized original title). The real name is listed
        // first; if we don't skip aliases, the trailing alias wins last-write and we
        // show "Cike Wu Liu Qi" instead of the French "Scissor Seven". Keep real names.
        if n["isAlias"].as_bool() == Some(true) {
            continue;
        }
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

/// Entities whose table has a `raw_translations` cache column (series & movies use
/// the bundled `?meta=translations` path; episodes/seasons don't).
fn raw_translations_table(entity_type: &str) -> Option<&'static str> {
    match entity_type {
        "series" => Some("catalog.series"),
        "movie" => Some("catalog.movie"),
        _ => None,
    }
}

/// One-off catalog-wide backfill: re-fetch the `?meta=translations` bundle for every
/// series and movie and re-ingest it through [`store_bundle`], which now (a) stores
/// the real translated names instead of TheTVDB's `isAlias` romanizations and (b)
/// caches the raw bundle in `raw_translations` for future offline re-derivation.
///
/// Resumable: an entity is skipped once `raw_translations` is set, so re-running
/// continues where it left off. Mirrors regardless of `CATALOG_MODE` (calls TheTVDB
/// directly), matching the episode-translation backfill. Returns entities processed.
pub async fn backfill_all_bundles(state: &AppState) -> AppResult<u64> {
    let series = backfill_bundles(state, "series").await?;
    let movies = backfill_bundles(state, "movie").await?;
    Ok(series + movies)
}

async fn backfill_bundles(state: &AppState, entity_type: &str) -> AppResult<u64> {
    use std::sync::Arc;
    use std::sync::atomic::{AtomicU64, Ordering};
    use tokio::sync::Semaphore;

    let tbl = table(entity_type);
    // Separate process with its own pool: keep concurrency modest so it plus the live
    // server don't exhaust Postgres. The TheTVDB client's global pacer caps total rps.
    let concurrency = std::env::var("BACKFILL_CONCURRENCY")
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .filter(|&n| n > 0)
        .unwrap_or(8);

    let sem = Arc::new(Semaphore::new(concurrency));
    let done = Arc::new(AtomicU64::new(0));
    let mut cursor = 0i64;
    loop {
        // Page through ids not yet backfilled (raw_translations still NULL); the cursor
        // advances past each page so a failing entity can't loop within this run.
        let ids: Vec<i64> = sqlx::query_scalar(&format!(
            "SELECT id FROM {tbl} WHERE id > $1 AND NOT deleted AND raw_translations IS NULL \
             ORDER BY id LIMIT 2000"
        ))
        .bind(cursor)
        .fetch_all(&state.db)
        .await?;
        if ids.is_empty() {
            break;
        }
        cursor = *ids.last().unwrap();

        let mut set = tokio::task::JoinSet::new();
        for id in ids {
            let permit = sem.clone().acquire_owned().await.expect("semaphore closed");
            let st = state.clone();
            let et = entity_type.to_string();
            let done = done.clone();
            set.spawn(async move {
                let _permit = permit; // released when this entity finishes → next starts
                if let Err(e) = backfill_one(&st, &et, id).await {
                    tracing::warn!("translation-bundle backfill: {et} {id} failed: {e}");
                }
                let n = done.fetch_add(1, Ordering::Relaxed) + 1;
                if n % 500 == 0 {
                    tracing::info!("translation-bundle backfill ({et}): {n} processed");
                }
            });
        }
        while set.join_next().await.is_some() {}
    }
    Ok(done.load(Ordering::Relaxed))
}

/// Targeted backfill of specific catalog ids (series or movie, auto-detected by
/// which table holds the id). For testing the sweep or repairing individual entries
/// without a full run. Returns the number successfully re-ingested.
pub async fn backfill_ids(state: &AppState, ids: &[i64]) -> AppResult<u64> {
    let mut n = 0;
    for &id in ids {
        let kind: Option<String> = sqlx::query_scalar(
            "SELECT CASE \
               WHEN EXISTS (SELECT 1 FROM catalog.series WHERE id = $1) THEN 'series' \
               WHEN EXISTS (SELECT 1 FROM catalog.movie  WHERE id = $1) THEN 'movie'  END",
        )
        .bind(id)
        .fetch_one(&state.db)
        .await?;
        match kind.as_deref() {
            Some(kind) => match backfill_one(state, kind, id).await {
                Ok(()) => {
                    n += 1;
                    tracing::info!("translation-bundle backfill: {kind} {id} done");
                }
                Err(e) => tracing::warn!("translation-bundle backfill: {kind} {id} failed: {e}"),
            },
            None => tracing::warn!("translation-bundle backfill: id {id} not in series or movie"),
        }
    }
    Ok(n)
}

/// Fetch one entity's `?meta=translations` bundle and re-ingest it.
async fn backfill_one(state: &AppState, entity_type: &str, id: i64) -> AppResult<()> {
    let data = match entity_type {
        "movie" => state.tvdb.movie_extended_translated(id).await?,
        _ => state.tvdb.series_extended_translated(id).await?,
    };
    store_bundle(state, entity_type, id, &data).await
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

/// Bulk-upsert many translation rows of one type/language in a SINGLE statement
/// (used when mirroring translations from the episodes-by-language endpoint). One
/// round-trip per page instead of one per row keeps DB connection churn low.
/// COALESCE keeps any existing name/overview when the incoming value is NULL, so a
/// partial fetch never wipes a good translation.
pub async fn store_many(
    state: &AppState,
    entity_type: &str,
    lang: &str,
    ids: &[i64],
    names: &[Option<String>],
    overviews: &[Option<String>],
) -> AppResult<()> {
    if ids.is_empty() {
        return Ok(());
    }
    sqlx::query(
        "INSERT INTO catalog.translation (entity_type, entity_id, language, name, overview, last_synced_at) \
         SELECT $1, t.id, $2, t.name, t.overview, now() \
         FROM unnest($3::bigint[], $4::text[], $5::text[]) AS t(id, name, overview) \
         ON CONFLICT (entity_type, entity_id, language) DO UPDATE SET \
           name = COALESCE(EXCLUDED.name, catalog.translation.name), \
           overview = COALESCE(EXCLUDED.overview, catalog.translation.overview), \
           last_synced_at = now() \
         WHERE (EXCLUDED.name IS NOT NULL AND EXCLUDED.name IS DISTINCT FROM catalog.translation.name) \
            OR (EXCLUDED.overview IS NOT NULL AND EXCLUDED.overview IS DISTINCT FROM catalog.translation.overview)",
    )
    .bind(entity_type)
    .bind(lang)
    .bind(ids)
    .bind(names)
    .bind(overviews)
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
