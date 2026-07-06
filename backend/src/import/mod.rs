//! One-time GDPR export importer: reads the TV Time `.zip` and loads the user's
//! data into `app.*`. Idempotent (safe to re-run): the account is deduped by its
//! original TV Time id, and every write is an upsert. Derived datasets (stats
//! cache, addiction scores, count-by-timeframe) are intentionally skipped — we
//! recompute those. See `docs/datamining.md`.

pub mod gomap;
mod source;

#[cfg(test)]
mod tests;

use uuid::Uuid;
use std::collections::HashMap;

use anyhow::Context;

use crate::{catalog, state::AppState};
use source::{Row, ZipSource, boolv, i32v, i64v, s, ts_utc};

#[derive(Debug, Default, serde::Serialize)]
pub struct ImportSummary {
    pub user_id: Uuid,
    pub shows: usize,
    pub movies: usize,
    pub movies_matched: usize,
    pub movies_suggested: usize,
    pub favorites: usize,
    pub watch_events: usize,
    pub rewatches: usize,
    pub ratings: usize,
    pub series_prefetched: usize,
    pub series_prefetch_failed: usize,
    pub series_recovered: usize,
    pub series_suggested: usize,
}

/// Import from a zip on disk, creating a fresh user (deduped by original id). CLI
/// path — prefetches the referenced series into the catalog.
pub async fn run(state: &AppState, zip_path: &str) -> anyhow::Result<ImportSummary> {
    let src = ZipSource::open(zip_path)?;
    import(state, src, None, true).await
}

/// Import an uploaded zip's tracking data into an existing (logged-in) user.
/// Skips the slow catalog prefetch (read-through fills it lazily) so the upload
/// request returns promptly.
pub async fn run_into(state: &AppState, bytes: Vec<u8>, user_id: Uuid) -> anyhow::Result<ImportSummary> {
    let src = ZipSource::open_bytes(bytes)?;
    import(state, src, Some(user_id), false).await
}

/// Import a zip on disk into an existing user (repairs/refreshes their data).
/// Prefetches the catalog so posters/episodes are available. Used by the CLI to
/// backfill an account whose earlier import was partial.
pub async fn run_zip_into(state: &AppState, zip_path: &str, user_id: Uuid) -> anyhow::Result<ImportSummary> {
    let src = ZipSource::open(zip_path)?;
    import(state, src, Some(user_id), true).await
}

async fn import(
    state: &AppState,
    mut src: ZipSource,
    target_user: Option<Uuid>,
    prefetch: bool,
) -> anyhow::Result<ImportSummary> {
    // Load the CSVs we use (flat relational ones + the favorites list).
    let social = src.read_csv("user_social_data.csv")?;
    let personal = src.read_csv("user_personal_data.csv")?;
    let show_data = src.read_csv("user_tv_show_data.csv")?;
    let followed = src.read_csv("followed_tv_show.csv")?;
    let follow_src = src.read_csv("followed_tv_show_source.csv")?;
    let special = src.read_csv("user_show_special_status.csv")?;
    let seen_latest = src.read_csv("show_seen_episode_latest.csv")?;
    let lists = src.read_csv("lists-prod-lists.csv")?;
    let rewatched = src.read_csv("rewatched_episode.csv")?;
    let ratings = src.read_csv("ratings-v2-prod-votes.csv")?;
    let tracking = src.read_csv("tracking-prod-records-v2.csv")?;
    // Movies live only in the v1 tracking export (`entity_type = movie`); v2 is
    // episode-only. Series carry a TheTVDB id, but movies are identified solely
    // by a TV Time uuid + title, so they need name resolution (below).
    let tracking_v1 = src.read_csv("tracking-prod-records.csv")?;

    let mut summary = ImportSummary::default();

    // ---- user: either the logged-in account (upload) or a fresh internal id (CLI) ----
    let user_id = match target_user {
        Some(uid) => {
            // Bring over profile bits from the export without touching screen_name/email.
            update_profile_from_export(state, uid, &personal).await?;
            uid
        }
        None => upsert_user(state, &social, &personal).await?,
    };
    summary.user_id = user_id;

    // ---- favorites (only source of favorite status; is_favorited is 0 in show_data) ----
    let favorite_ids = parse_favorites(&lists);
    summary.favorites = favorite_ids.len();

    // ---- consolidated per-show relationship ----
    let shows = build_shows(&show_data, &followed, &follow_src, &special, &seen_latest, &favorite_ids);
    for (series_id, acc) in &shows {
        upsert_show(state, user_id, *series_id, acc).await?;
    }
    summary.shows = shows.len();

    // ---- rewatch counters, ratings, emotions ----
    summary.rewatches = import_rewatches(state, user_id, &rewatched).await?;
    summary.ratings = import_ratings(state, user_id, &ratings).await?;

    // ---- watch history (bulk, in one transaction) + TV Time's stats summary ----
    summary.watch_events = import_watch_events(state, user_id, &tracking).await?;
    import_stats(state, user_id, &tracking).await?;

    // ---- movies: stage the raw intent now (fast); resolve names below/in bg ----
    summary.movies = stage_movies(state, user_id, &tracking_v1).await?;

    // ---- prefetch referenced series into the catalog via read-through ----
    if prefetch {
        let (ok, failed) = prefetch_series(state, shows.keys().copied()).await;
        summary.series_prefetched = ok;
        summary.series_prefetch_failed = failed;
        // Recover the ids that 404'd by matching their imported name.
        let (applied, suggested) = resolve_unavailable(state, user_id).await;
        summary.series_recovered = applied;
        summary.series_suggested = suggested;
        // Resolve staged movie titles to catalog ids and add them to the library.
        let m = resolve_movies(state, user_id).await;
        summary.movies_matched = m.matched;
        summary.movies_suggested = m.suggested;
    }

    Ok(summary)
}

/// Apply the export's cover/bio/country to an existing user (in-app import),
/// leaving their screen_name/email/password untouched.
async fn update_profile_from_export(state: &AppState, user_id: Uuid, personal: &[Row]) -> anyhow::Result<()> {
    let (mut country, mut bio, mut cover) = (None, None, None);
    for r in personal {
        match s(r, "name") {
            Some("country-code") => country = s(r, "value").map(str::to_string),
            Some("bio") => bio = s(r, "value").map(str::to_string),
            Some("cover") => cover = s(r, "value").map(str::to_string),
            _ => {}
        }
    }
    sqlx::query(
        "UPDATE app.users SET cover_url = COALESCE($2, cover_url), bio = COALESCE($3, bio), \
                country_code = COALESCE($4, country_code), updated_at = now() WHERE id = $1",
    )
    .bind(user_id)
    .bind(cover)
    .bind(bio)
    .bind(country)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Prefetch every series the user tracks into the catalog (via read-through) so
/// the library shows names/posters. Run in the background after an in-app import.
pub async fn prefetch_user_series(state: &AppState, user_id: Uuid) {
    let ids: Vec<i64> = sqlx::query_scalar("SELECT series_id FROM app.user_show WHERE user_id = $1")
        .bind(user_id)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default();
    let total = ids.len();
    let (ok, failed) = prefetch_series(state, ids.into_iter()).await;
    tracing::info!("import prefetch for user {user_id}: {ok}/{total} ok, {failed} failed");
    // Best-effort recovery of the dead ids by matching the imported name.
    resolve_unavailable(state, user_id).await;
    // Resolve staged movie titles to catalog ids and add them to the library.
    resolve_movies(state, user_id).await;
}

/// Sweep every distinct series id in any user's library through the read-through,
/// flagging the ids that 404 on TheTVDB as unavailable. Backfills the flag for
/// data imported before that column existed. Returns (ok, flagged).
pub async fn backfill_unavailable(state: &AppState) -> (usize, usize) {
    let ids: Vec<i64> = sqlx::query_scalar("SELECT DISTINCT series_id FROM app.user_show")
        .fetch_all(&state.db)
        .await
        .unwrap_or_default();
    let total = ids.len();
    let (ok, failed) = prefetch_series(state, ids.into_iter()).await;
    tracing::info!("backfill_unavailable: {ok}/{total} resolved, {failed} flagged/failed");
    (ok, failed)
}

async fn upsert_user(state: &AppState, social: &[Row], personal: &[Row]) -> anyhow::Result<Uuid> {
    let s0 = social.first().context("user_social_data.csv is empty")?;
    let external = i64v(s0, "user_id").context("user_social_data.user_id missing")?;

    let (mut country, mut bio, mut cover) = (None, None, None);
    for r in personal {
        match s(r, "name") {
            Some("country-code") => country = s(r, "value").map(str::to_string),
            Some("bio") => bio = s(r, "value").map(str::to_string),
            Some("cover") => cover = s(r, "value").map(str::to_string),
            _ => {}
        }
    }

    // Reuse the existing internal id if this account was imported before;
    // otherwise assign a fresh one.
    let existing: Option<Uuid> =
        sqlx::query_scalar("SELECT id FROM app.users WHERE external_tvtime_id = $1")
            .bind(external)
            .fetch_optional(&state.db)
            .await?;
    let user_id = existing.unwrap_or_else(Uuid::now_v7);

    sqlx::query(
        "INSERT INTO app.users \
           (id, external_tvtime_id, screen_name, gender, birthday, bio, country_code, cover_url, created_at, updated_at) \
         VALUES ($1,$2,$3,$4,$5::date,$6,$7,$8, COALESCE($9::timestamptz, now()), COALESCE($10::timestamptz, now())) \
         ON CONFLICT (id) DO UPDATE SET \
           external_tvtime_id=EXCLUDED.external_tvtime_id, screen_name=EXCLUDED.screen_name, \
           gender=EXCLUDED.gender, birthday=EXCLUDED.birthday, bio=EXCLUDED.bio, \
           country_code=EXCLUDED.country_code, cover_url=EXCLUDED.cover_url, updated_at=now()",
    )
    .bind(user_id)
    .bind(external)
    .bind(s(s0, "screen_name").unwrap_or("user"))
    .bind(s(s0, "gender"))
    .bind(s(s0, "birthday"))
    .bind(bio)
    .bind(country)
    .bind(cover)
    .bind(ts_utc(s0, "created_at"))
    .bind(ts_utc(s0, "updated_at"))
    .execute(&state.db)
    .await?;

    tracing::info!("user {external} → internal id {user_id}");
    Ok(user_id)
}

fn parse_favorites(lists: &[Row]) -> Vec<i64> {
    lists
        .iter()
        .filter(|r| s(r, "s_key") == Some("favorite-series"))
        .filter_map(|r| s(r, "objects"))
        .flat_map(gomap::parse_favorite_objects)
        .filter(|it| it.kind == "series")
        .map(|it| it.id)
        .collect()
}

#[derive(Default)]
struct ShowAcc {
    name: Option<String>,
    is_followed: bool,
    is_favorited: bool,
    nb_seen: i32,
    active: Option<bool>,
    archived: Option<bool>,
    diffusion: Option<String>,
    notif_type: Option<i32>,
    notif_offset: Option<i32>,
    follow_source: Option<String>,
    status: Option<String>,
    last_seen_episode_id: Option<i64>,
    created_at: Option<String>,
    followed_at: Option<String>,
}

fn build_shows(
    show_data: &[Row],
    followed: &[Row],
    follow_src: &[Row],
    special: &[Row],
    seen_latest: &[Row],
    favorite_ids: &[i64],
) -> HashMap<i64, ShowAcc> {
    let mut map: HashMap<i64, ShowAcc> = HashMap::new();

    for r in show_data {
        if let Some(id) = i64v(r, "tv_show_id") {
            let a = map.entry(id).or_default();
            a.name = s(r, "tv_show_name").map(str::to_string);
            a.is_followed = boolv(r, "is_followed").unwrap_or(false);
            a.nb_seen = i32v(r, "nb_episodes_seen").unwrap_or(0);
        }
    }
    for r in followed {
        if let Some(id) = i64v(r, "tv_show_id") {
            let a = map.entry(id).or_default();
            a.active = boolv(r, "active");
            a.archived = boolv(r, "archived");
            a.diffusion = s(r, "diffusion").map(str::to_string);
            a.notif_type = i32v(r, "notification_type");
            a.notif_offset = i32v(r, "notification_offset");
            a.created_at = ts_utc(r, "created_at");
            a.followed_at = ts_utc(r, "created_at");
        }
    }
    for r in follow_src {
        if let Some(id) = i64v(r, "tv_show_id") {
            map.entry(id).or_default().follow_source = s(r, "source").map(str::to_string);
        }
    }
    for r in special {
        if let Some(id) = i64v(r, "tv_show_id") {
            map.entry(id).or_default().status = s(r, "status").map(str::to_string);
        }
    }
    for r in seen_latest {
        if let Some(id) = i64v(r, "tv_show_id") {
            map.entry(id).or_default().last_seen_episode_id = i64v(r, "episode_id");
        }
    }
    for &id in favorite_ids {
        map.entry(id).or_default().is_favorited = true;
    }
    map
}

async fn upsert_show(state: &AppState, user_id: Uuid, series_id: i64, a: &ShowAcc) -> anyhow::Result<()> {
    sqlx::query(
        "INSERT INTO app.user_show \
           (user_id, series_id, is_followed, is_favorited, status, archived, active, diffusion, \
            follow_source, notification_type, notification_offset, nb_episodes_seen, \
            last_seen_episode_id, followed_at, created_at, updated_at, import_name) \
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13, \
                 $14::timestamptz, COALESCE($15::timestamptz, now()), now(), $16) \
         ON CONFLICT (user_id, series_id) DO UPDATE SET \
           is_followed=EXCLUDED.is_followed, is_favorited=EXCLUDED.is_favorited, status=EXCLUDED.status, \
           archived=EXCLUDED.archived, active=EXCLUDED.active, diffusion=EXCLUDED.diffusion, \
           follow_source=EXCLUDED.follow_source, notification_type=EXCLUDED.notification_type, \
           notification_offset=EXCLUDED.notification_offset, nb_episodes_seen=EXCLUDED.nb_episodes_seen, \
           last_seen_episode_id=EXCLUDED.last_seen_episode_id, followed_at=EXCLUDED.followed_at, \
           import_name=COALESCE(EXCLUDED.import_name, app.user_show.import_name), updated_at=now()",
    )
    .bind(user_id)
    .bind(series_id)
    .bind(a.is_followed)
    .bind(a.is_favorited)
    .bind(a.status.as_deref())
    .bind(a.archived.unwrap_or(false))
    .bind(a.active.unwrap_or(true))
    .bind(a.diffusion.as_deref())
    .bind(a.follow_source.as_deref())
    .bind(a.notif_type)
    .bind(a.notif_offset)
    .bind(a.nb_seen)
    .bind(a.last_seen_episode_id)
    .bind(a.followed_at.as_deref())
    .bind(a.created_at.as_deref())
    .bind(a.name.as_deref())
    .execute(&state.db)
    .await?;
    Ok(())
}

async fn import_rewatches(state: &AppState, user_id: Uuid, rows: &[Row]) -> anyhow::Result<usize> {
    let mut n = 0;
    for r in rows {
        let Some(episode_id) = i64v(r, "episode_id") else { continue };
        sqlx::query(
            "INSERT INTO app.episode_rewatch (user_id, episode_id, count, updated_at) \
             VALUES ($1,$2,$3, COALESCE($4::timestamptz, now())) \
             ON CONFLICT (user_id, episode_id) DO UPDATE SET count=EXCLUDED.count, updated_at=now()",
        )
        .bind(user_id)
        .bind(episode_id)
        .bind(i32v(r, "cpt").unwrap_or(1))
        .bind(ts_utc(r, "updated_at"))
        .execute(&state.db)
        .await?;
        n += 1;
    }
    Ok(n)
}

async fn import_ratings(state: &AppState, user_id: Uuid, rows: &[Row]) -> anyhow::Result<usize> {
    let mut n = 0;
    for r in rows {
        let Some(episode_id) = i64v(r, "episode_id") else { continue };
        // vote_key = "{episode_id}-{user_id}-{vote}"
        let vote: i16 = s(r, "vote_key")
            .and_then(|k| k.rsplit('-').next())
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);
        sqlx::query(
            "INSERT INTO app.episode_rating (user_id, episode_id, vote, uuid, created_at) \
             VALUES ($1,$2,$3,$4::uuid, now()) \
             ON CONFLICT (user_id, episode_id) DO UPDATE SET vote=EXCLUDED.vote, uuid=EXCLUDED.uuid",
        )
        .bind(user_id)
        .bind(episode_id)
        .bind(vote)
        .bind(s(r, "uuid"))
        .execute(&state.db)
        .await?;
        n += 1;
    }
    Ok(n)
}

/// Import the watch history from tracking-prod-records-v2 as `app.watch_event`
/// rows as `app.watch_event` — ONE row per episode watch. Only records that carry
/// an `episode_id` are watches; the export also contains per-series follow rows
/// (`key=user-series-…`) and a single stats-summary row (`key=tracking-stats`)
/// with no episode_id — those are NOT movie watches (there are no per-movie rows in
/// this export) so we skip them here. `key`/`uuid` gives idempotency.
async fn import_watch_events(state: &AppState, user_id: Uuid, rows: &[Row]) -> anyhow::Result<usize> {
    let mut tx = state.db.begin().await?;
    let mut n = 0;
    for r in rows {
        // Skip anything that isn't an actual episode watch.
        let Some(episode_id) = i64v(r, "episode_id") else { continue };
        let series_id = i64v(r, "s_id");

        let source_uuid = s(r, "key")
            .or_else(|| s(r, "uuid"))
            .map(str::to_string)
            .unwrap_or_else(|| format!("{}-{episode_id}-{}", series_id.unwrap_or(0), s(r, "created_at").unwrap_or("")));
        let is_rewatch = s(r, "key").is_some_and(|k| k.contains("rewatch"))
            || s(r, "bulk_type") == Some("rewatch");

        sqlx::query(
            "INSERT INTO app.watch_event \
               (user_id, entity_type, series_id, episode_id, season_number, \
                episode_number, runtime, is_rewatch, bulk_type, source_uuid, watched_at, created_at) \
             VALUES ($1,'episode',$2,$3,$4,$5,$6,$7,$8,$9, COALESCE($10::timestamptz, now()), now()) \
             ON CONFLICT (user_id, source_uuid) DO NOTHING",
        )
        .bind(user_id)
        .bind(series_id)
        .bind(episode_id)
        .bind(i32v(r, "season_number").or_else(|| i32v(r, "s_no")))
        .bind(i32v(r, "episode_number").or_else(|| i32v(r, "ep_no")))
        .bind(i32v(r, "runtime"))
        .bind(is_rewatch)
        .bind(s(r, "bulk_type"))
        .bind(&source_uuid)
        .bind(ts_utc(r, "created_at"))
        .execute(&mut *tx)
        .await?;
        n += 1;
    }
    tx.commit().await?;
    Ok(n)
}

/// Import TV Time's stats-summary row (`key=tracking-stats`) — the authoritative
/// movie count + total watch time (runtimes in SECONDS) — onto the user.
async fn import_stats(state: &AppState, user_id: Uuid, rows: &[Row]) -> anyhow::Result<()> {
    let Some(r) = rows.iter().find(|r| s(r, "key") == Some("tracking-stats")) else { return Ok(()) };
    sqlx::query(
        "UPDATE app.users SET \
           stat_movies = $2, stat_episode_watches = $3, \
           stat_series_runtime_secs = $4, stat_movies_runtime_secs = $5, updated_at = now() \
         WHERE id = $1",
    )
    .bind(user_id)
    .bind(i32v(r, "movie_watch_count"))
    .bind(i32v(r, "ep_watch_count"))
    .bind(i64v(r, "total_series_runtime"))
    .bind(i64v(r, "total_movies_runtime"))
    .execute(&state.db)
    .await?;
    Ok(())
}

// ---- movies -----------------------------------------------------------------
//
// The TV Time export has no TheTVDB movie id: a movie is just a random uuid, a
// title (usually the original/Japanese one), an optional romanized alpha slug, a
// year and a runtime, spread across `follow` / `watch` / `towatch` rows in the v1
// tracking CSV. We accumulate those per uuid, stage the watched ones, then (in the
// prefetch phase) resolve each title to a catalog movie by TheTVDB search.

#[derive(Default)]
struct MovieAcc {
    name: Option<String>,        // original title (movie_name)
    search_name: Option<String>, // romanized/English title from the alpha slug
    year: Option<i32>,
    runtime_secs: Option<i32>,
    watched: bool,               // has at least one `watch` row
    watched_count: i32,          // watches + rewatches
    watchlist: bool,             // has a `towatch` (plan-to-watch) row
    last_watched: Option<String>,
    followed_at: Option<String>,
}

/// Group the v1 tracking export's movie rows (`entity_type = movie`) by TV Time's
/// movie uuid into one accumulator each. Non-movie rows are ignored.
fn build_movies(records: &[Row]) -> HashMap<String, MovieAcc> {
    let mut map: HashMap<String, MovieAcc> = HashMap::new();
    for r in records {
        if s(r, "entity_type") != Some("movie") {
            continue;
        }
        let Some(uuid) = s(r, "uuid") else { continue };
        let a = map.entry(uuid.to_string()).or_default();
        if a.name.is_none() {
            a.name = s(r, "movie_name").map(str::to_string);
        }
        if a.search_name.is_none() {
            a.search_name = movie_search_name(r);
        }
        if a.year.is_none() {
            a.year = movie_year(r);
        }
        if a.runtime_secs.is_none() {
            a.runtime_secs = i32v(r, "runtime");
        }
        match s(r, "type") {
            Some("watch") => {
                a.watched = true;
                a.watched_count += 1;
                let w = ts_utc(r, "created_at");
                if w.as_deref() > a.last_watched.as_deref() {
                    a.last_watched = w;
                }
            }
            Some("rewatch_count") => a.watched_count += i32v(r, "rewatch_count").unwrap_or(0),
            Some("follow") => a.followed_at = ts_utc(r, "created_at"),
            Some("towatch") => a.watchlist = true,
            _ => {}
        }
    }
    map
}

/// The romanized/English title carried in the `*-alpha-<slug>` range key, e.g.
/// `follow-alpha-demon-slayer-infinity-train` → "demon slayer infinity train".
/// TheTVDB indexes original + romanized titles, so this searches better than the
/// (usually Japanese) `movie_name`.
fn movie_search_name(r: &Row) -> Option<String> {
    let slug = s(r, "alpha_range_key")?.split("-alpha-").nth(1)?;
    let name = slug.replace('-', " ");
    let name = name.trim();
    (!name.is_empty()).then(|| name.to_string())
}

/// Release year from the `release_date` cell ("YYYY-..."), ignoring TV Time's
/// zero-date sentinel ("0001-...").
fn movie_year(r: &Row) -> Option<i32> {
    let rd = s(r, "release_date")?;
    if rd.starts_with("0001") {
        return None;
    }
    rd.get(0..4)?.parse().ok()
}

/// Stage every *watched* or *plan-to-watch* movie from the export into
/// `app.import_movie` (idempotent per uuid). Entries with neither intent (e.g. a
/// bare follow with no watch/towatch) are skipped, as there's nothing to surface.
/// Returns the number staged.
async fn stage_movies(state: &AppState, user_id: Uuid, records: &[Row]) -> anyhow::Result<usize> {
    let movies = build_movies(records);
    let (mut staged, mut skipped) = (0usize, 0usize);
    for (uuid, a) in &movies {
        if !a.watched && !a.watchlist {
            skipped += 1;
            continue;
        }
        let search = a.search_name.clone().or_else(|| a.name.clone());
        sqlx::query(
            "INSERT INTO app.import_movie \
               (user_id, source_uuid, name, search_name, year, runtime_secs, \
                watched, watched_count, watchlist, last_watched, followed_at) \
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::timestamptz,$11::timestamptz) \
             ON CONFLICT (user_id, source_uuid) DO UPDATE SET \
               name=EXCLUDED.name, search_name=EXCLUDED.search_name, year=EXCLUDED.year, \
               runtime_secs=EXCLUDED.runtime_secs, watched=EXCLUDED.watched, \
               watched_count=EXCLUDED.watched_count, watchlist=EXCLUDED.watchlist, \
               last_watched=EXCLUDED.last_watched, followed_at=EXCLUDED.followed_at, updated_at=now()",
        )
        .bind(user_id)
        .bind(uuid)
        .bind(a.name.as_deref())
        .bind(search.as_deref())
        .bind(a.year)
        .bind(a.runtime_secs)
        .bind(a.watched)
        .bind(a.watched_count.max(1))
        .bind(a.watchlist)
        .bind(a.last_watched.as_deref())
        .bind(a.followed_at.as_deref())
        .execute(&state.db)
        .await?;
        staged += 1;
    }
    if staged > 0 || skipped > 0 {
        tracing::info!("stage_movies user {user_id}: {staged} staged (watched/plan-to-watch), {skipped} skipped");
    }
    Ok(staged)
}

#[derive(sqlx::FromRow)]
struct StagedMovie {
    source_uuid: String,
    name: Option<String>,
    search_name: Option<String>,
    year: Option<i32>,
}

/// Counts from a movie-resolution pass.
#[derive(Default)]
pub struct MovieResolveCounts {
    pub matched: usize,   // exact title hit → imported straight into the library
    pub suggested: usize, // uncertain hit → recorded for the user to confirm
    pub unmatched: usize, // no plausible match
}

/// Resolve each still-pending staged movie's title against TheTVDB. An **exact**
/// title match (name/translation/alias, year-preferred) is imported straight into
/// the library (`app.user_movie` + a `watch_event`). An **uncertain** match is
/// recorded as a `suggested` row for the user to confirm/reject in the same review
/// screen as dead-series recoveries. No plausible match → `unmatched`.
pub async fn resolve_movies(state: &AppState, user_id: Uuid) -> MovieResolveCounts {
    let pending: Vec<StagedMovie> = sqlx::query_as(
        "SELECT source_uuid, name, search_name, year FROM app.import_movie \
         WHERE user_id = $1 AND status = 'pending'",
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let mut c = MovieResolveCounts::default();
    for m in pending {
        let query = m.search_name.as_deref().or(m.name.as_deref()).map(str::trim).unwrap_or("");
        if query.is_empty() {
            continue;
        }
        match resolve_one_movie(state, query, m.year).await {
            MovieOutcome::Exact(movie_id) => {
                if let Err(e) = link_movie(state, user_id, &m.source_uuid, movie_id).await {
                    tracing::warn!("link movie \"{query}\" → {movie_id} failed: {e}");
                    continue;
                }
                c.matched += 1;
                tracing::info!("import movie \"{query}\" → catalog movie {movie_id} (exact)");
            }
            MovieOutcome::Uncertain { id, name, distance } => {
                if let Err(e) = suggest_movie(state, user_id, &m.source_uuid, id, &name, distance).await {
                    tracing::warn!("suggest movie \"{query}\" → {id} failed: {e}");
                    continue;
                }
                c.suggested += 1;
                tracing::info!("import movie \"{query}\" → suggests catalog movie {id} (\"{name}\", d={distance})");
            }
            MovieOutcome::None => {
                let _ = sqlx::query(
                    "UPDATE app.import_movie SET status='unmatched', updated_at=now() \
                     WHERE user_id=$1 AND source_uuid=$2",
                )
                .bind(user_id)
                .bind(&m.source_uuid)
                .execute(&state.db)
                .await;
                c.unmatched += 1;
                tracing::warn!("import movie unmatched: \"{query}\" (year {:?})", m.year);
            }
        }
    }
    if c.matched + c.suggested + c.unmatched > 0 {
        tracing::info!(
            "resolve_movies user {user_id}: {} matched, {} suggested, {} unmatched",
            c.matched, c.suggested, c.unmatched
        );
    }
    c
}

/// The tier of a movie title match (mirrors the dead-series `ResolveOutcome`).
enum MovieOutcome {
    /// Exact title hit → import automatically.
    Exact(i64),
    /// Uncertain fuzzy hit → record a suggestion for the user to confirm.
    Uncertain { id: i64, name: String, distance: i32 },
    None,
}

/// Search TheTVDB for a movie by title. An exact title hit (name/translation/alias)
/// — preferring one whose year matches the export — is [`MovieOutcome::Exact`]; a
/// close-but-uncertain fuzzy hit is [`MovieOutcome::Uncertain`]; otherwise `None`.
async fn resolve_one_movie(state: &AppState, name: &str, year: Option<i32>) -> MovieOutcome {
    let Ok(data) = state.tvdb.search(name, Some("movie")).await else { return MovieOutcome::None };
    let empty = Vec::new();
    let results = data.as_array().unwrap_or(&empty);

    let exacts: Vec<(i64, Option<i32>)> = results
        .iter()
        .filter_map(|r| exact_name_match(r, name).map(|id| (id, result_year(r))))
        .collect();
    if !exacts.is_empty() {
        if let Some(y) = year {
            if let Some((id, _)) = exacts.iter().find(|(_, ry)| ry.is_some_and(|v| (v - y).abs() <= 1)) {
                return MovieOutcome::Exact(*id);
            }
        }
        return MovieOutcome::Exact(exacts[0].0);
    }

    match best_fuzzy_match(results, name) {
        Some((id, name, distance)) => MovieOutcome::Uncertain { id, name, distance: distance as i32 },
        None => MovieOutcome::None,
    }
}

/// Record an uncertain movie match as a pending suggestion (caching the candidate's
/// poster so the review card can show it). Does NOT touch the user's library.
async fn suggest_movie(
    state: &AppState,
    user_id: Uuid,
    source_uuid: &str,
    movie_id: i64,
    name: &str,
    distance: i32,
) -> anyhow::Result<()> {
    let _ = catalog::movie::get(state, movie_id, Some("eng")).await;
    sqlx::query(
        "UPDATE app.import_movie SET status='suggested', suggested_movie_id=$3, \
                suggested_name=$4, distance=$5, updated_at=now() \
         WHERE user_id=$1 AND source_uuid=$2",
    )
    .bind(user_id)
    .bind(source_uuid)
    .bind(movie_id)
    .bind(name)
    .bind(distance)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Release year of a TheTVDB search result (the `year` field is a string).
fn result_year(r: &serde_json::Value) -> Option<i32> {
    r["year"]
        .as_str()
        .and_then(|s| s.get(0..4).and_then(|y| y.parse().ok()))
        .or_else(|| r["year"].as_i64().map(|v| v as i32))
}

/// Cache the resolved movie, add it to the user's library from the staged row, log
/// one watch event for history, and mark the staging row matched. All timestamps
/// stay in SQL (read straight from `app.import_movie`).
async fn link_movie(state: &AppState, user_id: Uuid, source_uuid: &str, movie_id: i64) -> anyhow::Result<()> {
    // Cache name/poster/runtime so the library can render the movie.
    let _ = catalog::movie::get(state, movie_id, Some("eng")).await;

    sqlx::query(
        "INSERT INTO app.user_movie \
           (user_id, movie_id, watched, watched_count, watchlist, last_watched, created_at, updated_at) \
         SELECT im.user_id, $3, im.watched, GREATEST(im.watched_count, 1), im.watchlist, im.last_watched, now(), now() \
         FROM app.import_movie im WHERE im.user_id = $1 AND im.source_uuid = $2 \
         ON CONFLICT (user_id, movie_id) DO UPDATE SET \
           watched = app.user_movie.watched OR EXCLUDED.watched, \
           watched_count = GREATEST(app.user_movie.watched_count, EXCLUDED.watched_count), \
           watchlist = app.user_movie.watchlist OR EXCLUDED.watchlist, \
           last_watched = GREATEST(app.user_movie.last_watched, EXCLUDED.last_watched), \
           updated_at = now()",
    )
    .bind(user_id)
    .bind(source_uuid)
    .bind(movie_id)
    .execute(&state.db)
    .await?;

    // One watch event (dated at the last watch) so the movie shows in history; the
    // deterministic source_uuid keeps re-imports idempotent.
    sqlx::query(
        "INSERT INTO app.watch_event (user_id, entity_type, movie_id, source_uuid, watched_at) \
         SELECT im.user_id, 'movie', $3, 'movie-import-' || im.source_uuid, COALESCE(im.last_watched, now()) \
         FROM app.import_movie im WHERE im.user_id = $1 AND im.source_uuid = $2 AND im.watched \
         ON CONFLICT (user_id, source_uuid) DO NOTHING",
    )
    .bind(user_id)
    .bind(source_uuid)
    .bind(movie_id)
    .execute(&state.db)
    .await?;

    sqlx::query(
        "UPDATE app.import_movie SET status='matched', resolved_movie_id=$3, updated_at=now() \
         WHERE user_id=$1 AND source_uuid=$2",
    )
    .bind(user_id)
    .bind(source_uuid)
    .bind(movie_id)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// How many series to fetch from TheTVDB concurrently. Each fetch is one HTTPS
/// round-trip (~0.3–0.4s of latency, mostly idle wait), so a serial loop over a
/// few hundred series is dominated by that wait — running a handful in parallel
/// cuts the wall-clock ~N×. Well below TheTVDB's rate limits.
const PREFETCH_CONCURRENCY: usize = 8;

async fn prefetch_series(state: &AppState, ids: impl Iterator<Item = i64>) -> (usize, usize) {
    use std::sync::Arc;
    use tokio::sync::Semaphore;

    let ids: Vec<i64> = ids.collect();
    let total = ids.len();
    let sem = Arc::new(Semaphore::new(PREFETCH_CONCURRENCY));
    let mut set = tokio::task::JoinSet::new();

    for id in ids {
        let state = state.clone();
        let sem = sem.clone();
        set.spawn(async move {
            let _permit = sem.acquire().await.expect("semaphore");
            match catalog::series::get(&state, id, Some("eng")).await {
                Ok(_) => {
                    mark_unavailable(&state, id, false).await;
                    // Cache the episode list too, so "up to date" / progress are
                    // computed correctly at import time (no need to open each show).
                    let _ = catalog::episode::list_for_series(&state, id, "default", Some("eng")).await;
                    true
                }
                // A 404 means the id was merged/deleted on TheTVDB — flag it (later
                // recovered by name in `resolve_unavailable`). Other errors (network,
                // rate limit, 5xx) are transient, so we leave the flag be.
                Err(crate::error::AppError::NotFound) => {
                    mark_unavailable(&state, id, true).await;
                    tracing::warn!("prefetch series {id}: not found on TheTVDB, flagged unavailable");
                    false
                }
                Err(e) => {
                    tracing::warn!("prefetch series {id} failed: {e}");
                    false
                }
            }
        });
    }

    let (mut ok, mut failed, mut done) = (0, 0, 0);
    while let Some(res) = set.join_next().await {
        if matches!(res, Ok(true)) { ok += 1 } else { failed += 1 }
        done += 1;
        if done % 50 == 0 {
            tracing::info!("prefetch progress: {done}/{total}");
        }
    }
    (ok, failed)
}

/// Max edit distance (on normalized names) for an uncertain fuzzy match.
const MAX_FUZZY_DISTANCE: usize = 2;

/// Outcome of trying to recover one dead series id.
enum ResolveOutcome {
    /// Exact-name match — remapped automatically.
    Applied,
    /// Uncertain fuzzy match — recorded as a pending suggestion for the user.
    Suggested,
    None,
}

/// Best-effort recovery of dead/merged TheTVDB ids for a user's library. For each
/// `unavailable` show we search TheTVDB by its imported name:
/// - an **exact** match (base name / any translation / any alias, case-insensitive)
///   is re-pointed automatically (tracking + watch history remapped);
/// - an **uncertain** match (normalized-equal or edit distance ≤ 2) is recorded as
///   a PENDING suggestion for the user to confirm/reject in the UI.
///
/// Returns `(applied, suggested)` counts.
pub async fn resolve_unavailable(state: &AppState, user_id: Uuid) -> (usize, usize) {
    let dead: Vec<(i64, Option<String>)> = sqlx::query_as(
        "SELECT series_id, import_name FROM app.user_show WHERE user_id = $1 AND unavailable \
           AND series_id NOT IN (SELECT dead_series_id FROM app.import_match WHERE user_id = $1)",
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await
    .unwrap_or_default();

    let (mut applied, mut suggested) = (0, 0);
    for (old_id, name) in dead {
        let Some(name) = name.as_deref().map(str::trim).filter(|s| !s.is_empty()) else { continue };
        match resolve_one(state, user_id, old_id, name).await {
            Ok(ResolveOutcome::Applied) => {
                applied += 1;
                tracing::info!("resolved dead series {old_id} (\"{name}\") automatically");
            }
            Ok(ResolveOutcome::Suggested) => {
                suggested += 1;
                tracing::info!("suggested a match for dead series {old_id} (\"{name}\")");
            }
            Ok(ResolveOutcome::None) => {}
            Err(e) => tracing::warn!("resolve series {old_id} (\"{name}\") failed: {e}"),
        }
    }
    if applied > 0 || suggested > 0 {
        tracing::info!("resolve_unavailable user {user_id}: {applied} auto-applied, {suggested} suggested");
    }
    (applied, suggested)
}

async fn resolve_one(
    state: &AppState,
    user_id: Uuid,
    old_id: i64,
    name: &str,
) -> anyhow::Result<ResolveOutcome> {
    let data = state.tvdb.search(name, Some("series")).await?;
    let empty = Vec::new();
    let results = data.as_array().unwrap_or(&empty);

    // Tier 1: exact match → apply automatically.
    if let Some(new_id) = results.iter().find_map(|r| exact_name_match(r, name)) {
        if new_id != old_id && catalog::series::get(state, new_id, Some("eng")).await.is_ok() {
            let _ = catalog::episode::list_for_series(state, new_id, "official", Some("eng")).await;
            remap_user_series(state, user_id, old_id, new_id).await?;
            return Ok(ResolveOutcome::Applied);
        }
    }

    // Tier 2: uncertain fuzzy match → record a suggestion (do NOT remap yet).
    if let Some((new_id, sug_name, dist)) = best_fuzzy_match(results, name) {
        if new_id != old_id && catalog::series::get(state, new_id, Some("eng")).await.is_ok() {
            sqlx::query(
                "INSERT INTO app.import_match \
                   (user_id, dead_series_id, import_name, suggested_series_id, suggested_name, distance) \
                 VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (user_id, dead_series_id) DO NOTHING",
            )
            .bind(user_id)
            .bind(old_id)
            .bind(name)
            .bind(new_id)
            .bind(&sug_name)
            .bind(dist as i32)
            .execute(&state.db)
            .await?;
            return Ok(ResolveOutcome::Suggested);
        }
    }

    Ok(ResolveOutcome::None)
}

/// A search result matches exactly iff the wanted name equals (case-insensitively)
/// its base name, any translation value, or any alias. Returns the result's id.
fn exact_name_match(r: &serde_json::Value, want: &str) -> Option<i64> {
    let want = want.trim();
    let hit = |s: &str| s.trim().eq_ignore_ascii_case(want);
    if candidate_names(r).iter().any(|c| hit(c)) {
        r["tvdb_id"].as_str().and_then(|s| s.parse().ok())
    } else {
        None
    }
}

/// The best uncertain match among search results: the candidate whose normalized
/// name is closest to the wanted name, within [`MAX_FUZZY_DISTANCE`] (distance 0 =
/// equal after normalization). Returns `(id, display_name, distance)`.
fn best_fuzzy_match(results: &[serde_json::Value], want: &str) -> Option<(i64, String, usize)> {
    let target: Vec<char> = normalize(want).chars().collect();
    if target.len() < 4 {
        return None; // too short to fuzzy-match safely
    }
    let mut best: Option<(i64, String, usize)> = None;
    for r in results {
        let Some(id) = r["tvdb_id"].as_str().and_then(|s| s.parse::<i64>().ok()) else { continue };
        let display = r["name"].as_str().unwrap_or(want).to_string();
        for cand in candidate_names(r) {
            let n: Vec<char> = normalize(&cand).chars().collect();
            if n.is_empty() {
                continue;
            }
            let d = levenshtein(&n, &target);
            // Accept a normalized-exact hit, or a small edit distance on names that
            // are long enough for it to be meaningful.
            let acceptable = d == 0 || (d <= MAX_FUZZY_DISTANCE && n.len().min(target.len()) >= 8);
            if acceptable && best.as_ref().is_none_or(|(_, _, bd)| d < *bd) {
                best = Some((id, display.clone(), d));
            }
        }
    }
    best
}

/// All comparable names on a search result: base name + translation values + aliases.
fn candidate_names(r: &serde_json::Value) -> Vec<String> {
    let mut names = Vec::new();
    if let Some(n) = r["name"].as_str() {
        names.push(n.to_string());
    }
    if let Some(tr) = r["translations"].as_object() {
        names.extend(tr.values().filter_map(|v| v.as_str()).map(str::to_string));
    }
    if let Some(al) = r["aliases"].as_array() {
        names.extend(al.iter().filter_map(|v| v.as_str()).map(str::to_string));
    }
    names
}

/// Normalize a title for fuzzy comparison: drop parenthetical/bracketed groups,
/// lowercase, and keep only alphanumerics (so punctuation, spacing and romanization
/// artifacts don't matter). E.g. `"Fate/stay night: UBW"` and `"Fate Stay Night UBW"`
/// normalize equal.
fn normalize(s: &str) -> String {
    let mut out = String::new();
    let mut depth: i32 = 0;
    for c in s.chars() {
        match c {
            '(' | '[' | '{' => depth += 1,
            ')' | ']' | '}' => depth = (depth - 1).max(0),
            _ if depth == 0 && c.is_alphanumeric() => out.extend(c.to_lowercase()),
            _ => {}
        }
    }
    out
}

/// Levenshtein edit distance between two char slices (two-row DP).
fn levenshtein(a: &[char], b: &[char]) -> usize {
    let (n, m) = (a.len(), b.len());
    if n == 0 {
        return m;
    }
    if m == 0 {
        return n;
    }
    let mut prev: Vec<usize> = (0..=m).collect();
    let mut cur = vec![0usize; m + 1];
    for i in 1..=n {
        cur[0] = i;
        for j in 1..=m {
            let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            cur[j] = (prev[j] + 1).min(cur[j - 1] + 1).min(prev[j - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut cur);
    }
    prev[m]
}

/// A pending fuzzy-match suggestion, enriched with the candidate's poster. Covers
/// both dead-series recoveries (`entity_type = "series"`) and uncertain movie
/// imports (`entity_type = "movie"`); `suggested_series_id` carries the suggested
/// catalog id in either case (a series id or a movie id).
#[derive(serde::Serialize, sqlx::FromRow)]
pub struct MatchSuggestion {
    pub id: i64,
    pub entity_type: String,
    pub import_name: String,
    pub suggested_series_id: i64,
    pub suggested_name: Option<String>,
    pub image_url: Option<String>,
    pub distance: i32,
}

/// Pending match suggestions for a user (closest first), across both dead-series
/// recoveries and uncertain movie imports. `langs` resolves the candidate's name to
/// the user's preferred language when a translation is cached (falling back to the
/// base name, which for anime is often Japanese).
pub async fn list_suggestions(
    state: &AppState,
    user_id: Uuid,
    langs: &[String],
) -> crate::error::AppResult<Vec<MatchSuggestion>> {
    let mut rows = sqlx::query_as::<_, MatchSuggestion>(
        "SELECT m.id, 'series' AS entity_type, m.import_name, m.suggested_series_id, \
                COALESCE( \
                  (SELECT tr.name FROM catalog.translation tr \
                   WHERE tr.entity_type = 'series' AND tr.entity_id = m.suggested_series_id \
                     AND tr.name IS NOT NULL AND tr.language = ANY($2) \
                   ORDER BY array_position($2, tr.language) LIMIT 1), \
                  s.name, m.suggested_name) AS suggested_name, \
                s.image_url, m.distance \
         FROM app.import_match m \
         LEFT JOIN catalog.series s ON s.id = m.suggested_series_id \
         WHERE m.user_id = $1 AND m.status = 'pending' \
         ORDER BY m.distance, m.import_name",
    )
    .bind(user_id)
    .bind(langs)
    .fetch_all(&state.db)
    .await?;

    let movies = sqlx::query_as::<_, MatchSuggestion>(
        "SELECT im.id, 'movie' AS entity_type, \
                COALESCE(im.search_name, im.name, '') AS import_name, \
                im.suggested_movie_id AS suggested_series_id, \
                COALESCE( \
                  (SELECT tr.name FROM catalog.translation tr \
                   WHERE tr.entity_type = 'movie' AND tr.entity_id = im.suggested_movie_id \
                     AND tr.name IS NOT NULL AND tr.language = ANY($2) \
                   ORDER BY array_position($2, tr.language) LIMIT 1), \
                  m.name, im.suggested_name) AS suggested_name, \
                m.image_url, COALESCE(im.distance, 0) AS distance \
         FROM app.import_movie im \
         LEFT JOIN catalog.movie m ON m.id = im.suggested_movie_id \
         WHERE im.user_id = $1 AND im.status = 'suggested' \
         ORDER BY im.distance, import_name",
    )
    .bind(user_id)
    .bind(langs)
    .fetch_all(&state.db)
    .await?;

    // Merge, closest first (series and movies interleaved by match confidence).
    rows.extend(movies);
    rows.sort_by(|a, b| a.distance.cmp(&b.distance).then_with(|| a.import_name.cmp(&b.import_name)));
    Ok(rows)
}

/// Confirm a suggestion: remap the dead series to the suggested live one and mark
/// it confirmed. Returns false if the suggestion doesn't exist / isn't pending.
pub async fn confirm_suggestion(state: &AppState, user_id: Uuid, id: i64) -> crate::error::AppResult<bool> {
    let row: Option<(i64, i64)> = sqlx::query_as(
        "SELECT dead_series_id, suggested_series_id FROM app.import_match \
         WHERE id = $1 AND user_id = $2 AND status = 'pending'",
    )
    .bind(id)
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?;
    let Some((dead, suggested)) = row else { return Ok(false) };

    // Make sure the live series + episodes are cached (episodes power the S/E remap).
    let _ = catalog::series::get(state, suggested, Some("eng")).await;
    let _ = catalog::episode::list_for_series(state, suggested, "official", Some("eng")).await;
    remap_user_series(state, user_id, dead, suggested).await?;

    sqlx::query("UPDATE app.import_match SET status = 'confirmed' WHERE id = $1")
        .bind(id)
        .execute(&state.db)
        .await?;
    Ok(true)
}

/// Reject a suggestion: leave the dead series hidden (`unavailable`) and remember
/// the rejection so we don't suggest it again.
pub async fn reject_suggestion(state: &AppState, user_id: Uuid, id: i64) -> crate::error::AppResult<bool> {
    let n = sqlx::query(
        "UPDATE app.import_match SET status = 'rejected' \
         WHERE id = $1 AND user_id = $2 AND status = 'pending'",
    )
    .bind(id)
    .bind(user_id)
    .execute(&state.db)
    .await?
    .rows_affected();
    Ok(n > 0)
}

/// Confirm an uncertain movie suggestion: import the suggested movie into the
/// user's library. Returns false if the suggestion doesn't exist / isn't pending.
pub async fn confirm_movie_suggestion(state: &AppState, user_id: Uuid, id: i64) -> crate::error::AppResult<bool> {
    let row: Option<(String, Option<i64>)> = sqlx::query_as(
        "SELECT source_uuid, suggested_movie_id FROM app.import_movie \
         WHERE id = $1 AND user_id = $2 AND status = 'suggested'",
    )
    .bind(id)
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?;
    let Some((source_uuid, Some(movie_id))) = row else { return Ok(false) };
    link_movie(state, user_id, &source_uuid, movie_id).await?;
    Ok(true)
}

/// Reject an uncertain movie suggestion: leave it out of the library and remember
/// the rejection so it isn't suggested again.
pub async fn reject_movie_suggestion(state: &AppState, user_id: Uuid, id: i64) -> crate::error::AppResult<bool> {
    let n = sqlx::query(
        "UPDATE app.import_movie SET status='rejected', updated_at=now() \
         WHERE id = $1 AND user_id = $2 AND status = 'suggested'",
    )
    .bind(id)
    .bind(user_id)
    .execute(&state.db)
    .await?
    .rows_affected();
    Ok(n > 0)
}

/// Re-point a user's tracking + watch history from a dead series id to a live one,
/// remapping watch events to the new series' episodes by (season, episode) number.
/// Merges into an existing row if the user already tracks the new id.
pub async fn remap_user_series(
    state: &AppState,
    user_id: Uuid,
    old_id: i64,
    new_id: i64,
) -> anyhow::Result<()> {
    let mut tx = state.db.begin().await?;

    let already: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM app.user_show WHERE user_id = $1 AND series_id = $2)",
    )
    .bind(user_id)
    .bind(new_id)
    .fetch_one(&mut *tx)
    .await?;

    if already {
        // Merge: OR the follow/favorite flags into the surviving row, drop the dead one.
        sqlx::query(
            "UPDATE app.user_show n SET is_followed = n.is_followed OR o.is_followed, \
                    is_favorited = n.is_favorited OR o.is_favorited \
             FROM app.user_show o \
             WHERE n.user_id = $1 AND n.series_id = $3 AND o.user_id = $1 AND o.series_id = $2",
        )
        .bind(user_id)
        .bind(old_id)
        .bind(new_id)
        .execute(&mut *tx)
        .await?;
        sqlx::query("DELETE FROM app.user_show WHERE user_id = $1 AND series_id = $2")
            .bind(user_id)
            .bind(old_id)
            .execute(&mut *tx)
            .await?;
    } else {
        sqlx::query(
            "UPDATE app.user_show SET series_id = $3, unavailable = false \
             WHERE user_id = $1 AND series_id = $2",
        )
        .bind(user_id)
        .bind(old_id)
        .bind(new_id)
        .execute(&mut *tx)
        .await?;
    }

    // Move watch events to the new series, remapping episode_id by (season, number).
    sqlx::query(
        "UPDATE app.watch_event we SET series_id = $3, \
           episode_id = COALESCE( \
             (SELECT ne.id FROM catalog.episode ne \
              WHERE ne.series_id = $3 AND NOT ne.deleted \
                AND ne.season_number = we.season_number AND ne.number = we.episode_number \
              LIMIT 1), \
             we.episode_id) \
         WHERE we.user_id = $1 AND we.series_id = $2",
    )
    .bind(user_id)
    .bind(old_id)
    .bind(new_id)
    .execute(&mut *tx)
    .await?;

    // Recompute the surviving row's distinct-episodes-seen count.
    sqlx::query(
        "UPDATE app.user_show SET nb_episodes_seen = (\
             SELECT count(DISTINCT episode_id) FROM app.watch_event \
             WHERE user_id = $1 AND series_id = $2 AND episode_id IS NOT NULL) \
         WHERE user_id = $1 AND series_id = $2",
    )
    .bind(user_id)
    .bind(new_id)
    .execute(&mut *tx)
    .await?;

    tx.commit().await?;
    Ok(())
}

/// Flag (or clear) every user_show pointing at `series_id` — a dead TheTVDB id is
/// dead for everyone, and a recovered one should reappear.
async fn mark_unavailable(state: &AppState, series_id: i64, value: bool) {
    if let Err(e) = sqlx::query("UPDATE app.user_show SET unavailable = $2 WHERE series_id = $1")
        .bind(series_id)
        .bind(value)
        .execute(&state.db)
        .await
    {
        tracing::warn!("mark_unavailable({series_id}, {value}) failed: {e}");
    }
}
