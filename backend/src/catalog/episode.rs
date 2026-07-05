//! Read-through access to episodes.

use serde_json::Value;

use crate::{
    catalog::{TTL, as_i32, as_i64, models::EpisodeRow, translation},
    error::{AppError, AppResult},
    state::AppState,
};

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
pub async fn mirror_translations(state: &AppState, series_id: i64) -> AppResult<()> {
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
            let data = match state.tvdb.series_episodes(series_id, "default", Some(lang), page).await {
                Ok(d) => d,
                Err(AppError::NotFound) => break, // language not served for this series
                Err(e) => return Err(e),
            };
            let episodes = data["episodes"].as_array().cloned().unwrap_or_default();
            if episodes.is_empty() {
                break;
            }
            // Collect the page and write it in one bulk upsert (one DB round-trip
            // per page instead of one per episode).
            let mut ids = Vec::new();
            let mut names = Vec::new();
            let mut overviews = Vec::new();
            for e in &episodes {
                if let Some(id) = as_i64(&e["id"]) {
                    let name = e["name"].as_str().filter(|s| !s.is_empty()).map(str::to_string);
                    let overview = e["overview"].as_str().filter(|s| !s.is_empty()).map(str::to_string);
                    // Skip episodes the language has no actual text for (the endpoint
                    // returns nulls for those) so we don't write empty rows.
                    if name.is_some() || overview.is_some() {
                        ids.push(id);
                        names.push(name);
                        overviews.push(overview);
                    }
                }
            }
            translation::store_many(state, "episode", lang, &ids, &names, &overviews).await?;
            if episodes.len() < 500 {
                break; // last page
            }
            page += 1;
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
    use std::sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
    };

    // Process several series at once so the TheTVDB client's global rate pacer
    // stays fed and the sweep runs at up to THETVDB_MAX_RPS (never above it — the
    // pacer caps total throughput regardless of concurrency). Kept modest by
    // default: this bin runs as a SEPARATE process with its OWN DB pool, so it must
    // not consume so many connections that it (plus the live server) exhausts
    // Postgres. Tune with BACKFILL_CONCURRENCY.
    let concurrency = std::env::var("BACKFILL_CONCURRENCY")
        .ok()
        .and_then(|v| v.parse::<usize>().ok())
        .filter(|&n| n > 0)
        .unwrap_or(8);
    let done = Arc::new(AtomicU64::new(0));
    let mut cursor = 0i64;
    loop {
        let ids: Vec<i64> = sqlx::query_scalar(
            "SELECT id FROM catalog.series \
             WHERE id > $1 AND NOT deleted AND episode_translations_synced_at IS NULL \
             ORDER BY id LIMIT $2",
        )
        .bind(cursor)
        .bind((concurrency as i64) * 8)
        .fetch_all(&state.db)
        .await?;
        if ids.is_empty() {
            break;
        }
        cursor = *ids.last().unwrap(); // advance past the batch so failures don't loop this run

        for chunk in ids.chunks(concurrency) {
            let mut set = tokio::task::JoinSet::new();
            for &id in chunk {
                let st = state.clone();
                let done = done.clone();
                set.spawn(async move {
                    match mirror_translations(&st, id).await {
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
                        tracing::info!("episode-translation backfill: {n} series processed");
                    }
                });
            }
            while set.join_next().await.is_some() {}
        }
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
    lang: Option<&str>,
) -> AppResult<Vec<EpisodeRow>> {
    // Make sure the series exists (also caches it / its seasons).
    super::series::get(state, series_id, lang).await?;

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
            let data = state.tvdb.series_episodes(series_id, season_type, lang, page).await?;
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
    if let (Some(lang), true) = (lang, state.config.catalog_mode.allow_remote()) {
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

    let rows = sqlx::query_as::<_, EpisodeRow>(
        "SELECT e.id, e.series_id, e.season_number, e.number, e.absolute_number, \
                COALESCE(NULLIF(t.name, ''), e.name) AS name, \
                COALESCE(NULLIF(t.overview, ''), e.overview) AS overview, \
                e.aired::text AS aired, e.runtime, e.image_url \
         FROM catalog.episode e \
         LEFT JOIN catalog.translation t \
           ON t.entity_type = 'episode' AND t.entity_id = e.id AND t.language = $2 \
         WHERE e.series_id = $1 AND NOT e.deleted \
         ORDER BY e.season_number NULLS LAST, e.number NULLS LAST",
    )
    .bind(series_id)
    .bind(lang.unwrap_or(""))
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
