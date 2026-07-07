//! Read-through access to episodes.

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

use serde_json::Value;

use crate::{
    catalog::{TTL, as_i32, as_i64, models::EpisodeRow, translation},
    error::{AppError, AppResult},
    state::AppState,
};

/// Timing accumulators for the episode-translation backfill, so its logs show
/// where wall-clock goes: TheTVDB fetches vs DB upserts. Microseconds, summed
/// across all concurrent workers.
#[derive(Default)]
pub struct Metrics {
    fetch_us: AtomicU64,
    fetch_count: AtomicU64,
    insert_us: AtomicU64,
    insert_count: AtomicU64,
    rows: AtomicU64,
}

pub async fn get(state: &AppState, id: i64, lang: Option<&str>) -> AppResult<EpisodeRow> {
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT last_synced_at > now() - interval '{TTL}' \
         FROM catalog.episode WHERE id = $1 AND NOT deleted"
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    if fresh != Some(true) {
        if state.config.catalog_mode.allow_remote() {
            let data = state.tvdb.episode(id).await?;
            upsert(state, id, &data).await?;
        } else if fresh.is_none() {
            return Err(AppError::NotFound);
        }
    }

    let mut row = sqlx::query_as::<_, EpisodeRow>(
        "SELECT id, series_id, season_number, number, absolute_number, name, overview, \
                aired::text AS aired, runtime, image_url \
         FROM catalog.episode WHERE id = $1 AND NOT deleted",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    let applied =
        translation::apply(state, "episode", id, lang, &mut row.name, &mut row.overview).await?;
    row.language = applied;
    Ok(row)
}

/// Mirror EVERY available-language name/overview for a series' episodes into
/// `catalog.translation`, so Mirror mode (which never calls TheTVDB on view) can
/// serve translated episodes offline. Reads the set of languages each episode has
/// from the cached base records' `nameTranslations`/`overviewTranslations`, then
/// pulls the bulk episodes-by-language endpoint (which returns translated
/// name/overview) once per language. Direct client calls — meant to run from
/// enrichment / the backfill bin, so it mirrors regardless of `CATALOG_MODE`.
pub async fn mirror_translations(
    state: &AppState,
    series_id: i64,
    metrics: Option<&Metrics>,
) -> AppResult<()> {
    // The base episode records already hold the original language; only mirror the
    // OTHER languages any episode of this series actually has a translation for.
    let original: Option<String> =
        sqlx::query_scalar("SELECT original_language FROM catalog.series WHERE id = $1")
            .bind(series_id)
            .fetch_optional(&state.db)
            .await?
            .flatten();

    let langs: Vec<String> = sqlx::query_scalar(
        "SELECT DISTINCT lang FROM ( \
            SELECT jsonb_array_elements_text(raw -> 'nameTranslations') AS lang \
              FROM catalog.episode \
              WHERE series_id = $1 AND NOT deleted AND jsonb_typeof(raw -> 'nameTranslations') = 'array' \
            UNION \
            SELECT jsonb_array_elements_text(raw -> 'overviewTranslations') AS lang \
              FROM catalog.episode \
              WHERE series_id = $1 AND NOT deleted AND jsonb_typeof(raw -> 'overviewTranslations') = 'array' \
         ) t WHERE lang <> COALESCE($2, '') AND lang <> ''",
    )
    .bind(series_id)
    .bind(original.as_deref())
    .fetch_all(&state.db)
    .await?;

    for lang in &langs {
        let mut page = 0u32;
        loop {
            let fetch_started = Instant::now();
            let result = state.tvdb.series_episodes(series_id, "default", Some(lang), page).await;
            if let Some(m) = metrics {
                m.fetch_us.fetch_add(fetch_started.elapsed().as_micros() as u64, Ordering::Relaxed);
                m.fetch_count.fetch_add(1, Ordering::Relaxed);
            }
            let data = match result {
                Ok(d) => d,
                Err(AppError::NotFound) => break, // language not served for this series
                Err(e) => return Err(e),
            };
            let episodes = data["episodes"].as_array().cloned().unwrap_or_default();
            if episodes.is_empty() {
                break;
            }
            // Collect the page and write it in one bulk upsert (one DB round-trip
            // per page instead of one per episode). Dedupe by episode id: the
            // "default" ordering can list an episode more than once, and a bulk
            // ON CONFLICT can't update the same row twice in one statement.
            let mut seen = std::collections::HashSet::new();
            let mut ids = Vec::new();
            let mut names = Vec::new();
            let mut overviews = Vec::new();
            for e in &episodes {
                if let Some(id) = as_i64(&e["id"]) {
                    let name = e["name"].as_str().filter(|s| !s.is_empty()).map(str::to_string);
                    let overview = e["overview"].as_str().filter(|s| !s.is_empty()).map(str::to_string);
                    // Skip episodes the language has no actual text for (the endpoint
                    // returns nulls for those) so we don't write empty rows.
                    if (name.is_some() || overview.is_some()) && seen.insert(id) {
                        ids.push(id);
                        names.push(name);
                        overviews.push(overview);
                    }
                }
            }
            if !ids.is_empty() {
                let insert_started = Instant::now();
                translation::store_many(state, "episode", lang, &ids, &names, &overviews).await?;
                if let Some(m) = metrics {
                    m.insert_us.fetch_add(insert_started.elapsed().as_micros() as u64, Ordering::Relaxed);
                    m.insert_count.fetch_add(1, Ordering::Relaxed);
                    m.rows.fetch_add(ids.len() as u64, Ordering::Relaxed);
                }
            }
            if episodes.len() < 500 {
                break; // last page
            }
            page += 1;
        }
    }
    Ok(())
}

/// Mirror ONE episode's per-language name/overview. Used when `/updates` (re)syncs
/// a single episode (enqueued as "episode"), where the series-level bulk pass in
/// [`mirror_translations`] does not run — e.g. a newly aired episode or an edited
/// episode translation. Reads the episode's available languages from its cached base
/// record and pulls the per-episode translation endpoint for each, so ongoing
/// episode updates keep translations current.
pub async fn mirror_translations_for_episode(state: &AppState, episode_id: i64) -> AppResult<()> {
    let row: Option<(Option<i64>, Value)> = sqlx::query_as(
        "SELECT series_id, raw FROM catalog.episode WHERE id = $1 AND NOT deleted",
    )
    .bind(episode_id)
    .fetch_optional(&state.db)
    .await?;
    let Some((series_id, raw)) = row else { return Ok(()) };

    // The base record already holds the original language; skip it.
    let original: Option<String> = match series_id {
        Some(sid) => sqlx::query_scalar("SELECT original_language FROM catalog.series WHERE id = $1")
            .bind(sid)
            .fetch_optional(&state.db)
            .await?
            .flatten(),
        None => None,
    };

    let mut langs: Vec<String> = ["nameTranslations", "overviewTranslations"]
        .iter()
        .filter_map(|k| raw[*k].as_array())
        .flatten()
        .filter_map(|v| v.as_str())
        .filter(|l| !l.is_empty() && Some(*l) != original.as_deref())
        .map(str::to_string)
        .collect();
    langs.sort();
    langs.dedup();

    for lang in &langs {
        match state.tvdb.translation("episodes", episode_id, lang).await {
            Ok(data) => {
                let name = data["name"].as_str().filter(|s| !s.is_empty()).map(str::to_string);
                let overview = data["overview"].as_str().filter(|s| !s.is_empty()).map(str::to_string);
                if name.is_some() || overview.is_some() {
                    translation::store_many(state, "episode", lang, &[episode_id], &[name], &[overview]).await?;
                }
            }
            Err(AppError::NotFound) => {} // no translation for this language; skip
            Err(e) => return Err(e),
        }
    }
    Ok(())
}

/// Catalog-wide backfill of per-episode translations (see [`mirror_translations`]).
/// Resumable: a per-series marker (`episode_translations_synced_at`) is set on
/// success, and a cursor advances past failures within a run so one bad series
/// can't stall the sweep. Re-run to retry anything still unmarked. Returns the
/// number of series processed this run.
pub async fn backfill_all_translations(state: &AppState) -> AppResult<u64> {
    use std::sync::Arc;
    use tokio::sync::Semaphore;

    // Kept modest by default: this bin runs as a SEPARATE process with its OWN DB
    // pool, so it must not consume so many connections that it (plus the live
    // server) exhausts Postgres. Tune with BACKFILL_CONCURRENCY. The TheTVDB
    // client's global rate pacer caps total rps regardless of concurrency.
    let concurrency = std::env::var("BACKFILL_CONCURRENCY")
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .filter(|&n| n > 0)
        .unwrap_or(8);

    let metrics = Arc::new(Metrics::default());
    let done = Arc::new(AtomicU64::new(0));
    // Continuous worker pool: a permit is acquired BEFORE spawning each series, so
    // exactly `concurrency` run at once and the NEXT series starts the instant one
    // finishes. A slow, many-language series holds one permit but never idles the
    // other slots (unlike a per-batch barrier, which waits for the slowest).
    let sem = Arc::new(Semaphore::new(concurrency));
    let mut cursor = 0i64;
    loop {
        // Large page: the only barrier is per-page (fetch the next 2000 ids), which
        // is negligible against 2000 series of work.
        let ids: Vec<i64> = sqlx::query_scalar(
            "SELECT id FROM catalog.series \
             WHERE id > $1 AND NOT deleted AND episode_translations_synced_at IS NULL \
             ORDER BY id LIMIT 2000",
        )
        .bind(cursor)
        .fetch_all(&state.db)
        .await?;
        if ids.is_empty() {
            break;
        }
        cursor = *ids.last().unwrap(); // advance past the page so failures don't loop this run

        let mut set = tokio::task::JoinSet::new();
        for id in ids {
            let permit = sem.clone().acquire_owned().await.expect("semaphore closed");
            let st = state.clone();
            let done = done.clone();
            let metrics = metrics.clone();
            set.spawn(async move {
                let _permit = permit; // released when this series finishes → next starts
                match mirror_translations(&st, id, Some(&metrics)).await {
                    Ok(()) => {
                        let _ = sqlx::query(
                            "UPDATE catalog.series SET episode_translations_synced_at = now() WHERE id = $1",
                        )
                        .bind(id)
                        .execute(&st.db)
                        .await;
                    }
                    Err(e) => tracing::warn!("episode-translation backfill: series {id} failed: {e}"),
                }
                let n = done.fetch_add(1, Ordering::Relaxed) + 1;
                if n % 100 == 0 {
                    let fc = metrics.fetch_count.load(Ordering::Relaxed).max(1);
                    let ic = metrics.insert_count.load(Ordering::Relaxed).max(1);
                    tracing::info!(
                        "episode-translation backfill: {n} series | api: {} calls, avg {} ms | \
                         insert: {} stmts, avg {} ms, {} rows",
                        metrics.fetch_count.load(Ordering::Relaxed),
                        metrics.fetch_us.load(Ordering::Relaxed) / fc / 1000,
                        metrics.insert_count.load(Ordering::Relaxed),
                        metrics.insert_us.load(Ordering::Relaxed) / ic / 1000,
                        metrics.rows.load(Ordering::Relaxed),
                    );
                }
            });
        }
        while set.join_next().await.is_some() {}
    }
    Ok(done.load(Ordering::Relaxed))
}

/// Episodes of a series for a season-type (default `default`), fetched
/// read-through (all pages) and cached, then returned ordered. The bulk episode
/// list stays in the series' original language, so translated name/overview are
/// overlaid from the per-episode translation cache (warmed on first view).
pub async fn list_for_series(
    state: &AppState,
    series_id: i64,
    season_type: &str,
    langs: &[String],
) -> AppResult<Vec<EpisodeRow>> {
    // Highest-priority language drives the base episode-list fetch and series caching;
    // the full ordered list is used for the per-episode name/overview overlay below.
    let primary = langs.first().map(String::as_str);
    // Make sure the series exists (also caches it / its seasons).
    super::series::get(state, series_id, primary).await?;

    // episodes_synced_at is nullable → COALESCE so a NULL (never synced) decodes as false.
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT COALESCE(episodes_synced_at > now() - interval '{TTL}', false) \
         FROM catalog.series WHERE id = $1"
    ))
    .bind(series_id)
    .fetch_optional(&state.db)
    .await?;

    if fresh != Some(true) && state.config.catalog_mode.allow_remote() {
        let mut page = 0u32;
        loop {
            let data = state.tvdb.series_episodes(series_id, season_type, primary, page).await?;
            let episodes = data["episodes"].as_array().cloned().unwrap_or_default();
            if episodes.is_empty() {
                break;
            }
            for e in &episodes {
                if let Some(id) = as_i64(&e["id"]) {
                    upsert(state, id, e).await?;
                }
            }
            if episodes.len() < 500 {
                break; // last page
            }
            page += 1;
        }
        // Record when we last synced the episode list, and the non-special episode
        // count (for the "# episodes" filter).
        sqlx::query(
            "UPDATE catalog.series SET episodes_synced_at = now(), \
                episode_count = (SELECT count(*) FROM catalog.episode \
                                 WHERE series_id = $1 AND NOT deleted AND season_number > 0) \
             WHERE id = $1",
        )
        .bind(series_id)
        .execute(&state.db)
        .await?;
    }

    // Overlay per-episode translations for the requested language. TheTVDB only
    // translates an episode's name/overview via the per-episode translation
    // endpoint (the bulk episode list stays in the series' original language), so
    // warm the translation cache for any episodes missing a fresh entry, then read
    // it back with a COALESCE. Cached (incl. negative results), so this only calls
    // out on the first view per (series, language).
    // Warm the cache for EACH preferred language (non-mirror only; mirror serves
    // whatever is cached), so the best-language overlay below can fall back through
    // the list offline. Cached incl. negative results, so it only calls out once per
    // (series, language).
    if state.config.catalog_mode.allow_remote() {
        for lang in langs {
            let stale: Vec<i64> = sqlx::query_scalar(&format!(
                "SELECT e.id FROM catalog.episode e \
                 LEFT JOIN catalog.translation t \
                   ON t.entity_type = 'episode' AND t.entity_id = e.id AND t.language = $2 \
                 WHERE e.series_id = $1 AND NOT e.deleted \
                   AND (t.entity_id IS NULL OR t.last_synced_at <= now() - interval '{TTL}')"
            ))
            .bind(series_id)
            .bind(lang)
            .fetch_all(&state.db)
            .await?;
            translation::prefetch(state, "episode", &stale, lang).await;
        }
    }

    // LATERAL (not a plain LEFT JOIN): forces one indexed lookup per episode against
    // the translation PK (entity_type, entity_id, language). On production the
    // translation table is huge (all episodes x all languages), and a plain join lets
    // the planner flip to hashing/scanning that whole table for the language, which
    // measured ~14 s for a long series. The lateral keeps it a nested-loop index scan.
    let rows = sqlx::query_as::<_, EpisodeRow>(
        "SELECT e.id, e.series_id, e.season_number, e.number, e.absolute_number, \
                COALESCE(NULLIF(t.name, ''), e.name) AS name, \
                COALESCE(NULLIF(t.overview, ''), e.overview) AS overview, \
                e.aired::text AS aired, e.runtime, e.image_url \
         FROM catalog.episode e \
         LEFT JOIN LATERAL ( \
             SELECT tr.name, tr.overview FROM catalog.translation tr \
             WHERE tr.entity_type = 'episode' AND tr.entity_id = e.id AND tr.language = ANY($2) \
             ORDER BY array_position($2, tr.language) LIMIT 1 \
         ) t ON true \
         WHERE e.series_id = $1 AND NOT e.deleted \
         ORDER BY e.season_number NULLS LAST, e.number NULLS LAST",
    )
    .bind(series_id)
    .bind(langs)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// Force a re-fetch from TheTVDB and upsert (used by the /updates sync worker).
pub async fn refresh(state: &AppState, id: i64) -> AppResult<()> {
    let data = state.tvdb.episode(id).await?;
    upsert(state, id, &data).await
}

pub(crate) async fn upsert(state: &AppState, id: i64, data: &Value) -> AppResult<()> {
    let series_id = as_i64(&data["seriesId"]);
    let season_number = as_i32(&data["seasonNumber"]);
    let number = as_i32(&data["number"]);
    let absolute_number = as_i32(&data["absoluteNumber"]);
    let name = data["name"].as_str();
    let overview = data["overview"].as_str();
    // aired is "YYYY-MM-DD" or empty; cast to date in SQL, NULL when empty.
    let aired = data["aired"].as_str().filter(|s| !s.is_empty());
    let runtime = as_i32(&data["runtime"]);
    let image_url = super::image_url(&data["image"]);
    let is_movie = data["isMovie"].as_i64().map(|n| n != 0);
    let finale_type = data["finaleType"].as_str();
    let last_updated = data["lastUpdated"].as_str();

    sqlx::query(
        "INSERT INTO catalog.episode \
           (id, series_id, season_number, number, absolute_number, name, overview, aired, \
            runtime, image_url, is_movie, finale_type, raw, last_updated, last_synced_at, deleted) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8::date,$9,$10,$11,$12,$13, ($14::timestamp AT TIME ZONE 'UTC'), now(), false) \
         ON CONFLICT (id) DO UPDATE SET \
           series_id=EXCLUDED.series_id, season_number=EXCLUDED.season_number, number=EXCLUDED.number, \
           absolute_number=EXCLUDED.absolute_number, name=EXCLUDED.name, overview=EXCLUDED.overview, \
           aired=EXCLUDED.aired, runtime=EXCLUDED.runtime, image_url=EXCLUDED.image_url, \
           is_movie=EXCLUDED.is_movie, finale_type=EXCLUDED.finale_type, raw=EXCLUDED.raw, \
           last_updated=EXCLUDED.last_updated, last_synced_at=now(), deleted=false",
    )
    .bind(id)
    .bind(series_id)
    .bind(season_number)
    .bind(number)
    .bind(absolute_number)
    .bind(name)
    .bind(overview)
    .bind(aired)
    .bind(runtime)
    .bind(image_url)
    .bind(is_movie)
    .bind(finale_type)
    .bind(sqlx::types::Json(data))
    .bind(last_updated)
    .execute(&state.db)
    .await?;

    Ok(())
}
