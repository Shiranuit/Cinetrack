//! Tracking domain: a user's relationship to shows (follow/favorite/status),
//! watch history (mark episodes seen), and the social graph (follow users).
//! All functions operate on an already-authenticated `user_id`.

use uuid::Uuid;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::{catalog, error::AppResult, state::AppState};

pub mod movies;

fn now_unix() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() as i64
}

/// SQL expression that resolves a series' name in the caller's preferred language
/// order, falling back to the base `s.name`. `langs` is a bound `text[]` param
/// placeholder (e.g. `$2`); `id_col` is the series-id column (e.g. `us.series_id`).
fn translated_name_sql(id_col: &str, langs: &str) -> String {
    format!(
        "COALESCE((SELECT tr.name FROM catalog.translation tr \
           WHERE tr.entity_type = 'series' AND tr.entity_id = {id_col} AND tr.name IS NOT NULL \
             AND tr.language = ANY({langs}) \
           ORDER BY array_position({langs}, tr.language) LIMIT 1), s.name)"
    )
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct UserShowRow {
    pub series_id: i64,
    pub name: Option<String>,
    pub image_url: Option<String>,
    pub is_followed: bool,
    pub is_favorited: bool,
    pub status: Option<String>,
    pub archived: bool,
    pub nb_episodes_seen: i32,
    pub last_seen_episode_id: Option<i64>,
    pub rating: Option<i16>,
}

#[derive(serde::Serialize)]
pub struct WatchResult {
    pub episode_id: i64,
    pub series_id: Option<i64>,
    pub is_rewatch: bool,
    pub nb_episodes_seen: i32,
}

/// List the shows the user tracks, joined with catalog names/posters, names
/// resolved to the caller's preferred `langs`.
pub async fn list_shows(state: &AppState, user_id: Uuid, langs: &[String]) -> AppResult<Vec<UserShowRow>> {
    let name = translated_name_sql("us.series_id", "$2");
    let sql = format!(
        "SELECT us.series_id, {name} AS name, s.image_url, us.is_followed, us.is_favorited, \
                us.status, us.archived, us.nb_episodes_seen, us.last_seen_episode_id, us.rating \
         FROM app.user_show us \
         LEFT JOIN catalog.series s ON s.id = us.series_id \
         WHERE us.user_id = $1 AND NOT us.unavailable \
         ORDER BY name NULLS LAST"
    );
    let rows = sqlx::query_as::<_, UserShowRow>(&sql)
        .bind(user_id)
        .bind(langs)
        .fetch_all(&state.db)
        .await?;
    Ok(rows)
}

/// The user's relationship to a single series, or `None` if not tracked yet.
pub async fn get_show(
    state: &AppState,
    user_id: Uuid,
    series_id: i64,
    langs: &[String],
) -> AppResult<Option<UserShowRow>> {
    let name = translated_name_sql("us.series_id", "$3");
    let sql = format!(
        "SELECT us.series_id, {name} AS name, s.image_url, us.is_followed, us.is_favorited, \
                us.status, us.archived, us.nb_episodes_seen, us.last_seen_episode_id, us.rating \
         FROM app.user_show us \
         LEFT JOIN catalog.series s ON s.id = us.series_id \
         WHERE us.user_id = $1 AND us.series_id = $2"
    );
    let row = sqlx::query_as::<_, UserShowRow>(&sql)
        .bind(user_id)
        .bind(series_id)
        .bind(langs)
        .fetch_optional(&state.db)
        .await?;
    Ok(row)
}

/// Set (or clear with `None`) the user's 1..5 rating for a show (Hate/Dislike/OK/
/// Like/Love). Upserts the `user_show` row — rating a show you watched implicitly
/// tracks it.
pub async fn set_show_rating(
    state: &AppState,
    user_id: Uuid,
    series_id: i64,
    rating: Option<i16>,
) -> AppResult<()> {
    if let Some(r) = rating
        && !(1..=5).contains(&r)
    {
        return Err(crate::error::AppError::BadRequest("rating must be between 1 and 5".into()));
    }
    sqlx::query(
        "INSERT INTO app.user_show (user_id, series_id, rating) VALUES ($1, $2, $3) \
         ON CONFLICT (user_id, series_id) DO UPDATE SET rating = $3, updated_at = now()",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(rating)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Per-episode watch counts for a series (episode_id → times watched), so the UI
/// can show a ×N badge and a seen state.
pub async fn seen_episode_counts(
    state: &AppState,
    user_id: Uuid,
    series_id: i64,
) -> AppResult<Vec<(i64, i64)>> {
    let rows = sqlx::query_as::<_, (i64, i64)>(
        "SELECT episode_id, count(*)::bigint FROM app.watch_event \
         WHERE user_id = $1 AND series_id = $2 AND episode_id IS NOT NULL \
         GROUP BY episode_id",
    )
    .bind(user_id)
    .bind(series_id)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

// ---- library (categorized) ----

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct LibraryShow {
    pub series_id: i64,
    pub name: Option<String>,
    pub image_url: Option<String>,
    pub nb_episodes_seen: i32,
    pub status: Option<String>,
    pub archived: bool,
    pub is_favorited: bool,
    pub last_watched: Option<i64>, // unix epoch of most recent watch
    pub caught_up: bool,           // seen the latest-aired non-special episode
    pub total_episodes: i64,       // aired, non-special (season > 0)
    pub seen_episodes: i64,        // distinct watched, non-special
    pub is_anime: bool,            // original language is Japanese
    pub rating: Option<i16>,       // the viewer's own labeled 1..5 rating (INT2 column)
}

#[derive(serde::Serialize, Default)]
pub struct Library {
    pub watching: Vec<LibraryShow>,
    pub up_to_date: Vec<LibraryShow>,
    pub stale: Vec<LibraryShow>,
    pub not_started: Vec<LibraryShow>,
    pub for_later: Vec<LibraryShow>,
    pub stopped: Vec<LibraryShow>,
}

/// A show is "stale" if not watched in this many days.
const STALE_DAYS: i64 = 30;

/// The user's tracked shows, grouped into UI categories; names resolved to `langs`.
/// `sort` orders shows WITHIN each category (default = recency), so the categorized
/// view honours the same sort options as the flat filter.
pub async fn library(state: &AppState, user_id: Uuid, langs: &[String], sort: &str, desc: bool) -> AppResult<Library> {
    // Whitelisted column + direction (never interpolate raw input into SQL). Default
    // and "popularity" keep the familiar most-recently-watched-first ordering.
    let dir = if desc { "DESC" } else { "ASC" };
    let col = match sort {
        "name" => "name",
        "rating" => "(SELECT avg(rating) FROM app.user_show WHERE series_id = lib.series_id AND rating IS NOT NULL)",
        "my_rating" => "lib.rating",
        "year" => "lib.year",
        "seasons" => "lib.season_count",
        "episodes" => "lib.episode_count",
        "runtime" => "lib.runtime",
        "updated" => "lib.last_updated",
        _ => "last_watched",
    };
    let order = format!("{col} {dir} NULLS LAST, name NULLS LAST");
    // Every per-series metric is aggregated ONCE (grouped by series_id) in a CTE
    // instead of as a correlated subquery evaluated per tracked show. The old
    // per-row `caught_up` EXISTS made Postgres re-scan the user's entire watch
    // history once per show (e.g. 313 shows × 5.5k watches ≈ 1.7M episode probes),
    // which measured ~3.3 s; this bulk form runs in ~45 ms for the same result.
    // `$1` = user_id, `$2` = preferred languages (text[]).
    let sql = &format!("\
        WITH lib AS ( \
            SELECT us.series_id, us.nb_episodes_seen, us.status, us.archived, us.is_favorited, us.rating, \
                   s.name AS base_name, s.image_url, s.original_language, \
                   s.year, s.season_count, s.episode_count, s.runtime, s.last_updated \
            FROM app.user_show us \
            LEFT JOIN catalog.series s ON s.id = us.series_id \
            WHERE us.user_id = $1 AND NOT us.unavailable \
                  AND (us.is_followed OR us.is_favorited OR us.archived OR us.status IS NOT NULL) \
        ), \
        ep AS ( \
            SELECT e.series_id, count(*) AS total_episodes, max(e.aired) AS max_aired \
            FROM catalog.episode e \
            WHERE e.series_id IN (SELECT series_id FROM lib) \
              AND NOT e.deleted AND e.season_number > 0 AND e.aired IS NOT NULL AND e.aired <= current_date \
            GROUP BY e.series_id \
        ), \
        latest_eps AS ( \
            SELECT e.series_id, e.id AS episode_id FROM catalog.episode e \
            JOIN ep ON ep.series_id = e.series_id AND e.aired = ep.max_aired \
            WHERE NOT e.deleted AND e.season_number > 0 \
        ), \
        lw AS ( \
            SELECT w.series_id, max(w.watched_at) AS last_watched FROM app.watch_event w \
            WHERE w.user_id = $1 AND w.series_id IN (SELECT series_id FROM lib) \
            GROUP BY w.series_id \
        ), \
        seen AS ( \
            SELECT w.series_id, count(DISTINCT w.episode_id) AS seen_episodes \
            FROM app.watch_event w \
            JOIN catalog.episode ce ON ce.id = w.episode_id AND ce.season_number > 0 \
            WHERE w.user_id = $1 AND w.series_id IN (SELECT series_id FROM lib) \
            GROUP BY w.series_id \
        ), \
        caught AS ( \
            SELECT DISTINCT le.series_id FROM latest_eps le \
            JOIN app.watch_event w ON w.user_id = $1 AND w.episode_id = le.episode_id \
        ) \
        SELECT lib.series_id, \
               COALESCE((SELECT tr.name FROM catalog.translation tr \
                         WHERE tr.entity_type = 'series' AND tr.entity_id = lib.series_id AND tr.name IS NOT NULL \
                           AND tr.language = ANY($2) \
                         ORDER BY array_position($2, tr.language) LIMIT 1), lib.base_name) AS name, \
               lib.image_url, lib.nb_episodes_seen, lib.status, lib.archived, lib.is_favorited, \
               extract(epoch FROM lw.last_watched)::bigint AS last_watched, \
               (caught.series_id IS NOT NULL) AS caught_up, \
               COALESCE(ep.total_episodes, 0)::bigint AS total_episodes, \
               COALESCE(seen.seen_episodes, 0)::bigint AS seen_episodes, \
               COALESCE(lib.original_language IN ('jpn','ja'), false) AS is_anime, \
               lib.rating \
        FROM lib \
        LEFT JOIN ep ON ep.series_id = lib.series_id \
        LEFT JOIN lw ON lw.series_id = lib.series_id \
        LEFT JOIN seen ON seen.series_id = lib.series_id \
        LEFT JOIN caught ON caught.series_id = lib.series_id \
        ORDER BY {order}");
    let started = std::time::Instant::now();
    let rows = sqlx::query_as::<_, LibraryShow>(sql)
        .bind(user_id)
        .bind(langs)
        .fetch_all(&state.db)
        .await?;
    // Expensive query: log its EXPLAIN plan, but only when this run actually exceeded
    // the profiling threshold — so a fast request stays quiet.
    if state.config.db_profile && started.elapsed().as_millis() as u64 >= state.config.db_profile_min_ms {
        let esql = crate::profile::explain_sql(sql);
        let eq = sqlx::query(&esql).bind(user_id).bind(langs);
        crate::profile::explain(&state.db, "tracking::library", eq).await;
    }

    let stale_cutoff = now_unix() - STALE_DAYS * 86400;
    let mut lib = Library::default();
    for r in rows {
        // "Started" = any real watch activity, not the (sometimes-zero) import
        // aggregate: a show with watch history must never be "Haven't started".
        let started = r.last_watched.is_some() || r.seen_episodes > 0 || r.nb_episodes_seen > 0;
        if r.archived || r.status.as_deref() == Some("stopped") {
            lib.stopped.push(r);
        } else if r.status.as_deref() == Some("for_later") {
            // Explicit "watch later" wins over the progress-based buckets.
            lib.for_later.push(r);
        } else if !started {
            lib.not_started.push(r);
        } else if r.caught_up {
            // Seen the latest-aired episode → caught up, regardless of how long ago.
            lib.up_to_date.push(r);
        } else if r.last_watched.is_none_or(|t| t < stale_cutoff) {
            lib.stale.push(r);
        } else {
            lib.watching.push(r);
        }
    }
    Ok(lib)
}

// ---- stats ----

#[derive(serde::Serialize, sqlx::FromRow, Default)]
pub struct Stats {
    pub episodes_seen: i64,   // distinct episodes
    pub episode_watches: i64, // incl. rewatches
    pub movies_seen: i64,
    pub total_minutes: i64,
    pub shows_followed: i64,
    pub favorites: i64,
}

pub async fn stats(state: &AppState, user_id: Uuid) -> AppResult<Stats> {
    // All figures derive from LIVE data so they update as you watch: episodes from
    // distinct watch rows, movies from `user_movie`, and watch time by summing each
    // watched episode's runtime (catalog episode runtime, else the series' average,
    // else the export's seconds→minutes) plus watched movies' runtimes.
    let s = sqlx::query_as::<_, Stats>(
        "SELECT \
           (SELECT count(DISTINCT episode_id) FROM app.watch_event \
            WHERE user_id=$1 AND entity_type='episode' AND episode_id IS NOT NULL)::bigint AS episodes_seen, \
           COALESCE(u.stat_episode_watches, \
             (SELECT count(*) FROM app.watch_event WHERE user_id=$1 AND entity_type='episode'))::bigint AS episode_watches, \
           (SELECT count(*) FROM app.user_movie WHERE user_id=$1 AND watched)::bigint AS movies_seen, \
           (\
             (SELECT COALESCE(sum(COALESCE(ce.runtime, s.runtime, we.runtime / 60.0)), 0) \
              FROM app.watch_event we \
              LEFT JOIN catalog.episode ce ON ce.id = we.episode_id AND NOT ce.deleted \
              LEFT JOIN catalog.series s ON s.id = we.series_id \
              WHERE we.user_id = $1 AND we.entity_type = 'episode') \
             + (SELECT COALESCE(sum(COALESCE(m.runtime, 0)), 0) \
                FROM app.watch_event we LEFT JOIN catalog.movie m ON m.id = we.movie_id \
                WHERE we.user_id = $1 AND we.entity_type = 'movie') \
           )::bigint AS total_minutes, \
           (SELECT count(*) FROM app.user_show WHERE user_id=$1 AND is_followed)::bigint AS shows_followed, \
           (SELECT count(*) FROM app.user_show WHERE user_id=$1 AND is_favorited)::bigint AS favorites \
         FROM app.users u WHERE u.id = $1",
    )
    .bind(user_id)
    .fetch_one(&state.db)
    .await?;
    Ok(s)
}

async fn ensure_series_cached(state: &AppState, series_id: i64) {
    // Best-effort: pull the series into the mirror so listings can show it.
    if let Err(e) = catalog::series::get(state, series_id, Some("eng")).await {
        tracing::warn!("could not cache series {series_id}: {e}");
    }
}

pub async fn set_followed(state: &AppState, user_id: Uuid, series_id: i64, value: bool) -> AppResult<()> {
    if value {
        ensure_series_cached(state, series_id).await;
    }
    sqlx::query(
        "INSERT INTO app.user_show (user_id, series_id, is_followed) VALUES ($1, $2, $3) \
         ON CONFLICT (user_id, series_id) DO UPDATE SET is_followed = EXCLUDED.is_followed, updated_at = now()",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(value)
    .execute(&state.db)
    .await?;
    Ok(())
}

pub async fn set_favorited(state: &AppState, user_id: Uuid, series_id: i64, value: bool) -> AppResult<()> {
    if value {
        ensure_series_cached(state, series_id).await;
    }
    sqlx::query(
        "INSERT INTO app.user_show (user_id, series_id, is_favorited) VALUES ($1, $2, $3) \
         ON CONFLICT (user_id, series_id) DO UPDATE SET is_favorited = EXCLUDED.is_favorited, updated_at = now()",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(value)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Set the special status (`for_later`, `stopped`, or `None` to clear).
/// `stopped` also flags the show archived ("stop watching").
pub async fn set_status(state: &AppState, user_id: Uuid, series_id: i64, status: Option<&str>) -> AppResult<()> {
    let archived = matches!(status, Some("stopped") | Some("archived"));
    sqlx::query(
        "INSERT INTO app.user_show (user_id, series_id, status, archived) VALUES ($1, $2, $3, $4) \
         ON CONFLICT (user_id, series_id) DO UPDATE SET status = EXCLUDED.status, archived = EXCLUDED.archived, updated_at = now()",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(status)
    .bind(archived)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Mark an episode seen: records a watch_event (flagged as a rewatch if already
/// seen) and recomputes the show's progress. Read-through-fetches the episode so
/// we know its series/season/number/runtime.
pub async fn watch_episode(state: &AppState, user_id: Uuid, episode_id: i64) -> AppResult<WatchResult> {
    let ep = catalog::episode::get(state, episode_id, None).await?;

    let seen_before: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM app.watch_event WHERE user_id = $1 AND episode_id = $2)",
    )
    .bind(user_id)
    .bind(episode_id)
    .fetch_one(&state.db)
    .await?;

    sqlx::query(
        "INSERT INTO app.watch_event \
           (user_id, entity_type, series_id, episode_id, season_number, episode_number, runtime, \
            is_rewatch, source_uuid, watched_at) \
         VALUES ($1, 'episode', $2, $3, $4, $5, $6, $7, gen_random_uuid()::text, now())",
    )
    .bind(user_id)
    .bind(ep.series_id)
    .bind(episode_id)
    .bind(ep.season_number)
    .bind(ep.number)
    .bind(ep.runtime)
    .bind(seen_before)
    .execute(&state.db)
    .await?;

    let nb = if let Some(sid) = ep.series_id {
        recompute_progress(state, user_id, sid).await?
    } else {
        0
    };

    Ok(WatchResult {
        episode_id,
        series_id: ep.series_id,
        is_rewatch: seen_before,
        nb_episodes_seen: nb,
    })
}

/// Decrement a watch: removes the most recent watch event for the episode (so a
/// ×N rewatch count goes down by one; hitting zero un-marks it as seen).
pub async fn unwatch_episode(state: &AppState, user_id: Uuid, episode_id: i64) -> AppResult<WatchResult> {
    let series_id: Option<i64> =
        sqlx::query_scalar("SELECT series_id FROM app.watch_event WHERE user_id = $1 AND episode_id = $2 LIMIT 1")
            .bind(user_id)
            .bind(episode_id)
            .fetch_optional(&state.db)
            .await?
            .flatten();

    sqlx::query(
        "DELETE FROM app.watch_event WHERE id = ( \
            SELECT id FROM app.watch_event \
            WHERE user_id = $1 AND episode_id = $2 \
            ORDER BY watched_at DESC LIMIT 1)",
    )
    .bind(user_id)
    .bind(episode_id)
    .execute(&state.db)
    .await?;

    let nb = if let Some(sid) = series_id {
        recompute_progress(state, user_id, sid).await?
    } else {
        0
    };

    Ok(WatchResult {
        episode_id,
        series_id,
        is_rewatch: false,
        nb_episodes_seen: nb,
    })
}

/// Recompute `nb_episodes_seen` (distinct episodes) and `last_seen_episode_id`
/// for a show from the watch history. Returns the new seen count.
async fn recompute_progress(state: &AppState, user_id: Uuid, series_id: i64) -> AppResult<i32> {
    sqlx::query(
        "INSERT INTO app.user_show (user_id, series_id, is_followed) VALUES ($1, $2, true) \
         ON CONFLICT (user_id, series_id) DO NOTHING",
    )
    .bind(user_id)
    .bind(series_id)
    .execute(&state.db)
    .await?;

    let nb: i32 = sqlx::query_scalar(
        "UPDATE app.user_show SET \
           nb_episodes_seen = (SELECT count(DISTINCT episode_id) FROM app.watch_event \
                               WHERE user_id = $1 AND series_id = $2 AND episode_id IS NOT NULL)::int, \
           last_seen_episode_id = (SELECT episode_id FROM app.watch_event \
                                   WHERE user_id = $1 AND series_id = $2 AND episode_id IS NOT NULL \
                                   ORDER BY watched_at DESC LIMIT 1), \
           updated_at = now() \
         WHERE user_id = $1 AND series_id = $2 \
         RETURNING nb_episodes_seen",
    )
    .bind(user_id)
    .bind(series_id)
    .fetch_one(&state.db)
    .await?;
    Ok(nb)
}

/// Mark every not-yet-watched episode of a season as watched (×1). Returns the
/// new distinct-seen count for the series.
pub async fn watch_season(state: &AppState, user_id: Uuid, series_id: i64, season: i32) -> AppResult<i32> {
    sqlx::query(
        "INSERT INTO app.watch_event \
           (user_id, entity_type, series_id, episode_id, season_number, episode_number, runtime, \
            is_rewatch, source_uuid, watched_at) \
         SELECT $1, 'episode', $2, e.id, e.season_number, e.number, e.runtime, false, \
                gen_random_uuid()::text, now() \
         FROM catalog.episode e \
         WHERE e.series_id = $2 AND e.season_number = $3 AND NOT e.deleted \
           AND NOT EXISTS (SELECT 1 FROM app.watch_event we WHERE we.user_id = $1 AND we.episode_id = e.id)",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(season)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Mark the UNSEEN episodes of a season up to (and including) `up_to` episode
/// number watched. Used to fill a gap when a user marks a later episode while
/// earlier ones are still unseen. Like [`watch_season`], it only touches episodes
/// with no existing watch, so already-seen episodes keep their count.
pub async fn watch_season_up_to(
    state: &AppState,
    user_id: Uuid,
    series_id: i64,
    season: i32,
    up_to: i32,
) -> AppResult<i32> {
    sqlx::query(
        "INSERT INTO app.watch_event \
           (user_id, entity_type, series_id, episode_id, season_number, episode_number, runtime, \
            is_rewatch, source_uuid, watched_at) \
         SELECT $1, 'episode', $2, e.id, e.season_number, e.number, e.runtime, false, \
                gen_random_uuid()::text, now() \
         FROM catalog.episode e \
         WHERE e.series_id = $2 AND e.season_number = $3 AND e.number <= $4 AND NOT e.deleted \
           AND NOT EXISTS (SELECT 1 FROM app.watch_event we WHERE we.user_id = $1 AND we.episode_id = e.id)",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(season)
    .bind(up_to)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Rewatch a whole season: adds one watch event for EVERY episode (increments
/// each episode's ×N count by one, regardless of prior state).
pub async fn rewatch_season(state: &AppState, user_id: Uuid, series_id: i64, season: i32) -> AppResult<i32> {
    sqlx::query(
        "INSERT INTO app.watch_event \
           (user_id, entity_type, series_id, episode_id, season_number, episode_number, runtime, \
            is_rewatch, source_uuid, watched_at) \
         SELECT $1, 'episode', $2, e.id, e.season_number, e.number, e.runtime, true, \
                gen_random_uuid()::text, now() \
         FROM catalog.episode e \
         WHERE e.series_id = $2 AND e.season_number = $3 AND NOT e.deleted",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(season)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Un-watch a whole season: removes all watch events for its episodes.
pub async fn unwatch_season(state: &AppState, user_id: Uuid, series_id: i64, season: i32) -> AppResult<i32> {
    sqlx::query(
        "DELETE FROM app.watch_event \
         WHERE user_id = $1 AND episode_id IN \
           (SELECT id FROM catalog.episode WHERE series_id = $2 AND season_number = $3)",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(season)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Decrement a whole season's watch counts by one: removes the single most recent
/// watch event of EACH episode that has any (the inverse of [`rewatch_season`], so
/// a ×N goes to ×(N-1) and a ×1 becomes unseen). Episodes with no watch are left
/// untouched.
pub async fn decrement_watch_season(state: &AppState, user_id: Uuid, series_id: i64, season: i32) -> AppResult<i32> {
    sqlx::query(
        "DELETE FROM app.watch_event WHERE id IN ( \
           SELECT DISTINCT ON (episode_id) id FROM app.watch_event \
           WHERE user_id = $1 AND episode_id IN \
             (SELECT id FROM catalog.episode WHERE series_id = $2 AND season_number = $3) \
           ORDER BY episode_id, watched_at DESC)",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(season)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Mark EVERY not-yet-watched episode of a series (all seasons, incl. specials)
/// as watched.
pub async fn watch_series(state: &AppState, user_id: Uuid, series_id: i64) -> AppResult<i32> {
    sqlx::query(
        "INSERT INTO app.watch_event \
           (user_id, entity_type, series_id, episode_id, season_number, episode_number, runtime, \
            is_rewatch, source_uuid, watched_at) \
         SELECT $1, 'episode', $2, e.id, e.season_number, e.number, e.runtime, false, \
                gen_random_uuid()::text, now() \
         FROM catalog.episode e \
         WHERE e.series_id = $2 AND NOT e.deleted \
           AND NOT EXISTS (SELECT 1 FROM app.watch_event we WHERE we.user_id = $1 AND we.episode_id = e.id)",
    )
    .bind(user_id)
    .bind(series_id)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Rewatch a whole series: one watch event for EVERY episode of every season
/// (increments each episode's ×N count by one, regardless of prior state).
pub async fn rewatch_series(state: &AppState, user_id: Uuid, series_id: i64) -> AppResult<i32> {
    sqlx::query(
        "INSERT INTO app.watch_event \
           (user_id, entity_type, series_id, episode_id, season_number, episode_number, runtime, \
            is_rewatch, source_uuid, watched_at) \
         SELECT $1, 'episode', $2, e.id, e.season_number, e.number, e.runtime, true, \
                gen_random_uuid()::text, now() \
         FROM catalog.episode e \
         WHERE e.series_id = $2 AND NOT e.deleted",
    )
    .bind(user_id)
    .bind(series_id)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Un-watch a whole series: remove all watch events for its episodes (keeps the
/// show in the library; use [`remove_show`] to drop it entirely).
pub async fn unwatch_series(state: &AppState, user_id: Uuid, series_id: i64) -> AppResult<i32> {
    sqlx::query(
        "DELETE FROM app.watch_event WHERE user_id = $1 AND series_id = $2 AND entity_type = 'episode'",
    )
    .bind(user_id)
    .bind(series_id)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Decrement a whole series' watch counts by one: removes the single most recent
/// watch event of EACH episode that has any (the inverse of [`rewatch_series`]).
/// Episodes with no watch are left untouched.
pub async fn decrement_watch_series(state: &AppState, user_id: Uuid, series_id: i64) -> AppResult<i32> {
    sqlx::query(
        "DELETE FROM app.watch_event WHERE id IN ( \
           SELECT DISTINCT ON (episode_id) id FROM app.watch_event \
           WHERE user_id = $1 AND series_id = $2 AND entity_type = 'episode' AND episode_id IS NOT NULL \
           ORDER BY episode_id, watched_at DESC)",
    )
    .bind(user_id)
    .bind(series_id)
    .execute(&state.db)
    .await?;
    recompute_progress(state, user_id, series_id).await
}

/// Remove a show from the user's library entirely (tracking row + watch history).
pub async fn remove_show(state: &AppState, user_id: Uuid, series_id: i64) -> AppResult<()> {
    let mut tx = state.db.begin().await?;
    sqlx::query("DELETE FROM app.watch_event WHERE user_id = $1 AND series_id = $2")
        .bind(user_id)
        .bind(series_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM app.user_show WHERE user_id = $1 AND series_id = $2")
        .bind(user_id)
        .bind(series_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(())
}

// ---- calendar ----

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct CalendarItem {
    pub series_id: i64,
    pub episode_id: Option<i64>,
    pub name: Option<String>,
    pub image_url: Option<String>,
    pub date: Option<String>,
    pub time: Option<String>,
    pub season_number: Option<i32>,
    pub episode_number: Option<i32>,
    pub episode_name: Option<String>,
    /// How many times the viewer has watched this episode (for the inline watch
    /// control on already-aired rows).
    pub watched_count: i64,
}

#[derive(serde::Serialize, Default)]
pub struct Calendar {
    pub upcoming: Vec<CalendarItem>,
    pub recent: Vec<CalendarItem>,
}

/// How far ahead / back the calendar looks.
const CALENDAR_UPCOMING_DAYS: i32 = 90;
/// Default depth of the "recently aired" section (one tap of "show older" extends
/// it further into the past).
const CALENDAR_RECENT_DAYS: i32 = 30;
/// Hard cap on how far back the recent window can be paged — a few months, so the
/// scan stays bounded rather than walking a show's whole aired history.
const CALENDAR_RECENT_MAX_DAYS: i32 = 180;

/// Upcoming (next 90 days) and recently-aired episodes for followed series — EVERY
/// scheduled episode in the window (from the mirrored episode list), not just the
/// single `nextAired`. Names resolved to `langs`. `recent_days` controls how far
/// back the recent section reaches (clamped to `[CALENDAR_RECENT_DAYS,
/// CALENDAR_RECENT_MAX_DAYS]`), letting the client page into the past.
pub async fn calendar(
    state: &AppState,
    me: Uuid,
    langs: &[String],
    recent_days: Option<i32>,
) -> AppResult<Calendar> {
    let recent_days = recent_days
        .unwrap_or(CALENDAR_RECENT_DAYS)
        .clamp(CALENDAR_RECENT_DAYS, CALENDAR_RECENT_MAX_DAYS);
    let name = translated_name_sql("us.series_id", "$2");
    // `cond` bounds e.aired; `dir` orders the window.
    let build = |cond: &str, dir: &str| {
        format!(
            "SELECT us.series_id, e.id AS episode_id, {name} AS name, s.image_url, \
                    e.aired::text AS date, NULLIF(s.raw->>'airsTime','') AS time, \
                    e.season_number, e.number AS episode_number, e.name AS episode_name, \
                    (SELECT count(*) FROM app.watch_event w \
                        WHERE w.user_id = us.user_id AND w.episode_id = e.id) AS watched_count \
             FROM app.user_show us \
             JOIN catalog.series s ON s.id = us.series_id \
             JOIN catalog.episode e ON e.series_id = us.series_id AND NOT e.deleted AND e.season_number > 0 \
             WHERE us.user_id = $1 AND us.is_followed AND NOT us.unavailable AND e.aired {cond} \
             ORDER BY e.aired {dir}, e.season_number, e.number LIMIT 300"
        )
    };

    let upcoming = sqlx::query_as::<_, CalendarItem>(&build(
        &format!("BETWEEN current_date AND current_date + interval '{CALENDAR_UPCOMING_DAYS} days'"),
        "ASC",
    ))
    .bind(me)
    .bind(langs)
    .fetch_all(&state.db)
    .await?;

    let recent = sqlx::query_as::<_, CalendarItem>(&build(
        &format!("BETWEEN current_date - interval '{recent_days} days' AND current_date - interval '1 day'"),
        "DESC",
    ))
    .bind(me)
    .bind(langs)
    .fetch_all(&state.db)
    .await?;

    Ok(Calendar { upcoming, recent })
}

/// Delete the user's account and all their data.
pub async fn delete_account(state: &AppState, user_id: Uuid) -> AppResult<()> {
    let mut tx = state.db.begin().await?;
    for q in [
        "DELETE FROM app.watch_event WHERE user_id = $1",
        "DELETE FROM app.episode_rating WHERE user_id = $1",
        "DELETE FROM app.episode_rewatch WHERE user_id = $1",
        "DELETE FROM app.list_item WHERE list_id IN (SELECT id FROM app.list WHERE user_id = $1)",
        "DELETE FROM app.list WHERE user_id = $1",
        "DELETE FROM app.user_show WHERE user_id = $1",
        "DELETE FROM app.user_follow WHERE follower_id = $1 OR followee_id = $1",
        "DELETE FROM app.users WHERE id = $1",
    ] {
        sqlx::query(q).bind(user_id).execute(&mut *tx).await?;
    }
    tx.commit().await?;
    Ok(())
}

// ---- social ----

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct UserBrief {
    pub id: Uuid,
    pub screen_name: String,
    pub avatar_url: Option<String>,
    pub is_private: bool,
    pub following: bool, // an accepted follow exists (me → them)
    pub requested: bool, // a pending request exists (me → them)
}

/// Another user's profile, with visibility respecting privacy.
#[derive(serde::Serialize, sqlx::FromRow)]
pub struct UserProfile {
    pub id: Uuid,
    pub screen_name: String,
    pub avatar_url: Option<String>,
    pub cover_url: Option<String>,
    pub bio: Option<String>,
    pub is_private: bool,
    pub is_self: bool,
    pub following: bool,      // me → them accepted
    pub requested: bool,      // me → them pending
    pub visible: bool,        // may I see the full profile?
    pub follower_count: i64,
    pub following_count: i64,
    pub profile_blocks: Vec<String>, // showcase layout chosen by this user
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct FeedItem {
    pub user_id: Uuid,
    pub screen_name: String,
    pub avatar_url: Option<String>,
    pub series_id: Option<i64>,
    pub series_name: Option<String>,
    pub series_image: Option<String>,
    pub episode_id: Option<i64>,
    pub season_number: Option<i32>,
    pub episode_number: Option<i32>,
    pub is_rewatch: bool,
    pub watched_at: Option<i64>,
}

/// The follow flags (accepted / pending) from `me` to another user, as SQL.
fn follow_flags_sql(target_col: &str) -> String {
    format!(
        "EXISTS(SELECT 1 FROM app.user_follow f WHERE f.follower_id = $1 AND f.followee_id = {target_col} AND f.status='accepted') AS following, \
         EXISTS(SELECT 1 FROM app.user_follow f WHERE f.follower_id = $1 AND f.followee_id = {target_col} AND f.status='pending') AS requested"
    )
}

/// Find users by (partial) screen name, flagged with our relationship to each.
pub async fn search_users(state: &AppState, me: Uuid, q: &str) -> AppResult<Vec<UserBrief>> {
    let flags = follow_flags_sql("u.id");
    let rows = sqlx::query_as::<_, UserBrief>(&format!(
        "SELECT u.id, u.screen_name, u.avatar_url, u.is_private, {flags} \
         FROM app.users u \
         WHERE u.id <> $1 AND u.screen_name ILIKE $2 \
         ORDER BY u.screen_name LIMIT 25"
    ))
    .bind(me)
    .bind(format!("%{q}%"))
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// Users the given user follows (accepted).
pub async fn following(state: &AppState, me: Uuid) -> AppResult<Vec<UserBrief>> {
    let rows = sqlx::query_as::<_, UserBrief>(
        "SELECT u.id, u.screen_name, u.avatar_url, u.is_private, true AS following, false AS requested \
         FROM app.user_follow f JOIN app.users u ON u.id = f.followee_id \
         WHERE f.follower_id = $1 AND f.status = 'accepted' ORDER BY u.screen_name",
    )
    .bind(me)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// People who follow me (accepted), flagged with whether I follow them back.
pub async fn followers(state: &AppState, me: Uuid) -> AppResult<Vec<UserBrief>> {
    let flags = follow_flags_sql("u.id");
    let rows = sqlx::query_as::<_, UserBrief>(&format!(
        "SELECT u.id, u.screen_name, u.avatar_url, u.is_private, {flags} \
         FROM app.user_follow f JOIN app.users u ON u.id = f.follower_id \
         WHERE f.followee_id = $1 AND f.status = 'accepted' ORDER BY u.screen_name"
    ))
    .bind(me)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// Remove one of my followers (delete their accepted follow of me).
pub async fn remove_follower(state: &AppState, me: Uuid, follower: Uuid) -> AppResult<()> {
    sqlx::query("DELETE FROM app.user_follow WHERE followee_id = $1 AND follower_id = $2")
        .bind(me)
        .bind(follower)
        .execute(&state.db)
        .await?;
    Ok(())
}

/// Incoming pending follow requests (people who want to follow me).
pub async fn follow_requests(state: &AppState, me: Uuid) -> AppResult<Vec<UserBrief>> {
    let flags = follow_flags_sql("u.id");
    let rows = sqlx::query_as::<_, UserBrief>(&format!(
        "SELECT u.id, u.screen_name, u.avatar_url, u.is_private, {flags} \
         FROM app.user_follow f JOIN app.users u ON u.id = f.follower_id \
         WHERE f.followee_id = $1 AND f.status = 'pending' ORDER BY f.created_at DESC"
    ))
    .bind(me)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// Accept a pending follow request from `follower`.
pub async fn accept_request(state: &AppState, me: Uuid, follower: Uuid) -> AppResult<bool> {
    let n = sqlx::query(
        "UPDATE app.user_follow SET status='accepted' \
         WHERE followee_id = $1 AND follower_id = $2 AND status = 'pending'",
    )
    .bind(me)
    .bind(follower)
    .execute(&state.db)
    .await?
    .rows_affected();
    Ok(n > 0)
}

/// Reject/remove a pending follow request from `follower`.
pub async fn reject_request(state: &AppState, me: Uuid, follower: Uuid) -> AppResult<bool> {
    let n = sqlx::query(
        "DELETE FROM app.user_follow WHERE followee_id = $1 AND follower_id = $2 AND status = 'pending'",
    )
    .bind(me)
    .bind(follower)
    .execute(&state.db)
    .await?
    .rows_affected();
    Ok(n > 0)
}

/// Another user's profile, respecting privacy: a private user's details are only
/// `visible` to themselves and accepted followers.
pub async fn user_profile(state: &AppState, me: Uuid, target: Uuid) -> AppResult<UserProfile> {
    let flags = follow_flags_sql("$2");
    let mut p = sqlx::query_as::<_, UserProfile>(&format!(
        "SELECT u.id, u.screen_name, u.avatar_url, u.cover_url, u.bio, u.is_private, \
                (u.id = $1) AS is_self, {flags}, \
                false AS visible, \
                (SELECT count(*) FROM app.user_follow WHERE followee_id = u.id AND status='accepted')::bigint AS follower_count, \
                (SELECT count(*) FROM app.user_follow WHERE follower_id = u.id AND status='accepted')::bigint AS following_count, \
                u.profile_blocks \
         FROM app.users u WHERE u.id = $2"
    ))
    .bind(me)
    .bind(target)
    .fetch_optional(&state.db)
    .await?
    .ok_or(crate::error::AppError::NotFound)?;

    // `visible` gates the CONTENT (shows/favorites/library); the identity — name,
    // avatar, cover background, bio — stays visible so a private profile still shows
    // "who" it is with a Follow button.
    p.visible = p.is_self || !p.is_private || p.following;
    Ok(p)
}

/// Whether `me` may see `target`'s profile details (public, self, or accepted follower).
pub async fn profile_visible(state: &AppState, me: Uuid, target: Uuid) -> AppResult<bool> {
    if me == target {
        return Ok(true);
    }
    let is_private: bool = sqlx::query_scalar("SELECT is_private FROM app.users WHERE id = $1")
        .bind(target)
        .fetch_optional(&state.db)
        .await?
        .ok_or(crate::error::AppError::NotFound)?;
    if !is_private {
        return Ok(true);
    }
    let accepted: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM app.user_follow WHERE follower_id = $1 AND followee_id = $2 AND status = 'accepted')",
    )
    .bind(me)
    .bind(target)
    .fetch_one(&state.db)
    .await?;
    Ok(accepted)
}

/// Another user's tracked shows — only when their profile is visible to `me`.
pub async fn user_shows(state: &AppState, me: Uuid, target: Uuid, langs: &[String]) -> AppResult<Vec<UserShowRow>> {
    if !profile_visible(state, me, target).await? {
        return Ok(vec![]);
    }
    list_shows(state, target, langs).await
}

/// Another user's categorized library (watching / up-to-date / stale / …) with
/// progress — only when their profile is visible to `me`.
pub async fn user_library(state: &AppState, me: Uuid, target: Uuid, langs: &[String]) -> AppResult<Library> {
    if !profile_visible(state, me, target).await? {
        return Ok(Library::default());
    }
    // Sort each category by the OWNER's own rating (highest first), matching how
    // the main library defaults — so a friend's shows read as their ranking.
    library(state, target, langs, "my_rating", true).await
}

/// Recent watch activity from the people the user follows.
pub async fn feed(state: &AppState, me: Uuid) -> AppResult<Vec<FeedItem>> {
    let rows = sqlx::query_as::<_, FeedItem>(
        "SELECT we.user_id, u.screen_name, u.avatar_url, we.series_id, \
                s.name AS series_name, s.image_url AS series_image, \
                we.episode_id, we.season_number, we.episode_number, we.is_rewatch, \
                extract(epoch FROM we.watched_at)::bigint AS watched_at \
         FROM app.watch_event we \
         JOIN app.users u ON u.id = we.user_id \
         LEFT JOIN catalog.series s ON s.id = we.series_id \
         WHERE we.entity_type = 'episode' \
           AND we.user_id IN (SELECT followee_id FROM app.user_follow WHERE follower_id = $1 AND status = 'accepted') \
         ORDER BY we.watched_at DESC LIMIT 60",
    )
    .bind(me)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}

/// Follow a user. Public users are followed immediately ('accepted'); private
/// users get a 'pending' request. Returns the resulting status.
pub async fn follow_user(state: &AppState, follower_id: Uuid, followee_id: Uuid) -> AppResult<String> {
    if follower_id == followee_id {
        return Err(crate::error::AppError::BadRequest("cannot follow yourself".into()));
    }
    let is_private: bool = sqlx::query_scalar("SELECT is_private FROM app.users WHERE id = $1")
        .bind(followee_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(crate::error::AppError::NotFound)?;
    let status = if is_private { "pending" } else { "accepted" };
    sqlx::query(
        "INSERT INTO app.user_follow (follower_id, followee_id, status) VALUES ($1, $2, $3) \
         ON CONFLICT (follower_id, followee_id) DO NOTHING",
    )
    .bind(follower_id)
    .bind(followee_id)
    .bind(status)
    .execute(&state.db)
    .await?;
    // Return the ACTUAL status (an existing accepted follow isn't downgraded).
    let actual: Option<String> =
        sqlx::query_scalar("SELECT status FROM app.user_follow WHERE follower_id = $1 AND followee_id = $2")
            .bind(follower_id)
            .bind(followee_id)
            .fetch_optional(&state.db)
            .await?;
    Ok(actual.unwrap_or_else(|| status.to_string()))
}

/// Set the current user's profile privacy.
pub async fn set_private(state: &AppState, user_id: Uuid, is_private: bool) -> AppResult<()> {
    sqlx::query("UPDATE app.users SET is_private = $2, updated_at = now() WHERE id = $1")
        .bind(user_id)
        .bind(is_private)
        .execute(&state.db)
        .await?;
    Ok(())
}

/// Persist the user's profile showcase layout (block keys, in display order).
pub async fn set_profile_blocks(state: &AppState, user_id: Uuid, blocks: &[String]) -> AppResult<()> {
    sqlx::query("UPDATE app.users SET profile_blocks = $2, updated_at = now() WHERE id = $1")
        .bind(user_id)
        .bind(blocks)
        .execute(&state.db)
        .await?;
    Ok(())
}

/// Set the user's preferred content languages (priority order). An empty list falls
/// back to English so a user is never left with no content language.
pub async fn set_languages(state: &AppState, user_id: Uuid, languages: &[String]) -> AppResult<()> {
    let langs: Vec<String> =
        if languages.is_empty() { vec!["eng".to_string()] } else { languages.to_vec() };
    sqlx::query("UPDATE app.users SET languages = $2, updated_at = now() WHERE id = $1")
        .bind(user_id)
        .bind(&langs)
        .execute(&state.db)
        .await?;
    Ok(())
}

pub async fn unfollow_user(state: &AppState, follower_id: Uuid, followee_id: Uuid) -> AppResult<()> {
    sqlx::query("DELETE FROM app.user_follow WHERE follower_id = $1 AND followee_id = $2")
        .bind(follower_id)
        .bind(followee_id)
        .execute(&state.db)
        .await?;
    Ok(())
}
