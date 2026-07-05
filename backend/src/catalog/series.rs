//! Read-through access to series.

use serde_json::Value;

use crate::{
    catalog::{TTL, as_i32, models::SeriesRow, translation},
    error::{AppError, AppResult},
    state::AppState,
};

/// Get a series, fetching from TheTVDB on cache miss / staleness, then overlaying
/// the `lang` translation (if any) onto name/overview.
pub async fn get(state: &AppState, id: i64, lang: Option<&str>) -> AppResult<SeriesRow> {
    let fresh: Option<bool> = sqlx::query_scalar(&format!(
        "SELECT last_synced_at > now() - interval '{TTL}' \
         FROM catalog.series WHERE id = $1 AND NOT deleted"
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?;

    if fresh != Some(true) {
        if state.config.catalog_mode.allow_remote() {
            let data = state.tvdb.series_extended(id).await?;
            upsert(state, id, &data).await?;
        } else if fresh.is_none() {
            // Mirror mode with nothing cached: no outbound call, so 404.
            return Err(AppError::NotFound);
        }
        // Mirror mode with a stale row: serve it as-is (offline-first).
    }

    let mut row = sqlx::query_as::<_, SeriesRow>(
        "SELECT id, name, slug, overview, status, year, runtime, image_url, original_language, score \
         FROM catalog.series WHERE id = $1 AND NOT deleted",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    let applied =
        translation::apply(state, "series", id, lang, &mut row.name, &mut row.overview).await?;
    row.language = applied.or_else(|| row.original_language.clone());
    Ok(row)
}

/// Rich metadata for the show page's "more details" view: facets (genres, themes,
/// networks, studios) plus scalars not on the base record's hot path.
#[derive(serde::Serialize, sqlx::FromRow)]
pub struct SeriesDetails {
    pub original_language: Option<String>,
    pub original_country: Option<String>,
    pub runtime: Option<i32>, // average episode length, minutes
    pub season_count: Option<i32>,
    pub episode_count: Option<i32>,
    /// Average of this app's users' 1..10 ratings, and how many rated it (TheTVDB's
    /// own `score` is a popularity metric, not a rating, so we don't surface it).
    pub community_rating: Option<f64>,
    pub rating_count: Option<i64>,
    pub aliases: Option<Vec<String>>,
    pub genres: Option<Vec<String>>,
    pub tags: Option<Vec<String>>, // themes
    pub networks: Option<Vec<String>>,
    pub studios: Option<Vec<String>>,
    pub first_aired: Option<String>,
    pub last_aired: Option<String>,
}

pub async fn details(state: &AppState, id: i64) -> AppResult<SeriesDetails> {
    // Ensure the series (and its facet links) are cached; single-flight coalesces
    // with the parallel `get` the show page also makes.
    get(state, id, None).await?;
    sqlx::query_as::<_, SeriesDetails>(
        "SELECT s.original_language, s.original_country, s.runtime, \
                s.season_count, s.episode_count, \
           (SELECT avg(rating)::float8 FROM app.user_show WHERE series_id = s.id AND rating IS NOT NULL) AS community_rating, \
           (SELECT count(*) FROM app.user_show WHERE series_id = s.id AND rating IS NOT NULL) AS rating_count, \
           s.aliases, \
           (SELECT array_agg(g.name ORDER BY g.name) FROM catalog.series_genre sg \
              JOIN catalog.genre g ON g.id = sg.genre_id WHERE sg.series_id = s.id) AS genres, \
           (SELECT array_agg(t.name ORDER BY t.name) FROM catalog.series_tag st \
              JOIN catalog.tag t ON t.id = st.tag_id WHERE st.series_id = s.id) AS tags, \
           (SELECT array_agg(c.name ORDER BY c.name) FROM catalog.series_company sc \
              JOIN catalog.company c ON c.id = sc.company_id \
              WHERE sc.series_id = s.id AND sc.kind = 'Network') AS networks, \
           (SELECT array_agg(c.name ORDER BY c.name) FROM catalog.series_company sc \
              JOIN catalog.company c ON c.id = sc.company_id \
              WHERE sc.series_id = s.id AND sc.kind = 'Studio') AS studios, \
           (SELECT min(aired)::text FROM catalog.episode \
              WHERE series_id = s.id AND NOT deleted AND season_number > 0) AS first_aired, \
           (SELECT max(aired)::text FROM catalog.episode \
              WHERE series_id = s.id AND NOT deleted AND season_number > 0) AS last_aired \
         FROM catalog.series s WHERE s.id = $1 AND NOT s.deleted",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)
}

/// Force a re-fetch from TheTVDB and upsert (used by the /updates sync worker).
pub async fn refresh(state: &AppState, id: i64) -> AppResult<()> {
    let data = state.tvdb.series_extended(id).await?;
    upsert(state, id, &data).await
}

/// Enrichment refresh: fetch the extended record **with all translations bundled**
/// (`?meta=translations`) and store both, so Discover/search show translated
/// titles for any language — offline, without a per-language fetch on view.
pub async fn refresh_full(state: &AppState, id: i64) -> AppResult<()> {
    let data = state.tvdb.series_extended_translated(id).await?;
    upsert(state, id, &data).await?;
    super::translation::store_bundle(state, "series", id, &data).await
}

async fn upsert(state: &AppState, id: i64, data: &Value) -> AppResult<()> {
    let name = data["name"].as_str();
    let slug = data["slug"].as_str();
    let overview = data["overview"].as_str();
    let status = data["status"]["name"].as_str();
    let year = as_i32(&data["year"]);
    let runtime = as_i32(&data["averageRuntime"]).or_else(|| as_i32(&data["runtime"]));
    let image_url = data["image"].as_str();
    let original_language = data["originalLanguage"].as_str();
    let original_country = data["originalCountry"].as_str().filter(|s| !s.is_empty());
    let score = data["score"].as_f64();
    let season_count = super::facets::season_count(data);
    let aliases = super::alias_names(data);
    // TheTVDB's own last-change time (a naive UTC datetime string). Advisory
    // metadata (drives the "recently updated" sort); NOT the sync dedup key.
    let last_updated = data["lastUpdated"].as_str();

    sqlx::query(
        "INSERT INTO catalog.series \
           (id, name, slug, overview, status, year, runtime, image_url, original_language, score, season_count, aliases, raw, last_updated, original_country, last_synced_at, deleted) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13, ($14::timestamp AT TIME ZONE 'UTC'), $15, now(), false) \
         ON CONFLICT (id) DO UPDATE SET \
           name=EXCLUDED.name, slug=EXCLUDED.slug, overview=EXCLUDED.overview, \
           status=EXCLUDED.status, year=EXCLUDED.year, runtime=EXCLUDED.runtime, \
           image_url=EXCLUDED.image_url, original_language=EXCLUDED.original_language, \
           score=EXCLUDED.score, season_count=EXCLUDED.season_count, aliases=EXCLUDED.aliases, raw=EXCLUDED.raw, \
           last_updated=EXCLUDED.last_updated, original_country=EXCLUDED.original_country, last_synced_at=now(), deleted=false",
    )
    .bind(id)
    .bind(name)
    .bind(slug)
    .bind(overview)
    .bind(status)
    .bind(year)
    .bind(runtime)
    .bind(image_url)
    .bind(original_language)
    .bind(score)
    .bind(season_count)
    .bind(&aliases)
    .bind(sqlx::types::Json(data))
    .bind(last_updated)
    .bind(original_country)
    .execute(&state.db)
    .await?;

    // The /extended payload embeds the season list — mirror those too (cheap, and
    // powers GET /api/series/{id}/seasons without an extra API call).
    if let Some(seasons) = data["seasons"].as_array() {
        for season in seasons {
            super::season::upsert_from_series(state, id, season).await?;
        }
    }

    // Refresh the normalized facet links (genres / tags / companies) for filtering.
    super::facets::upsert_series_facets(state, id, data).await?;

    Ok(())
}
