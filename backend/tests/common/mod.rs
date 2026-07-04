//! Shared harness for the DB integration tests.
//!
//! Every test runs against a THROWAWAY Postgres named by `TEST_DATABASE_URL`
//! (e.g. `postgres://tvshow:pw@localhost:5432/tvshow_test`). If that env var is
//! unset the tests SKIP (return early) so `cargo test` still passes with no DB.
//!
//!   TEST_DATABASE_URL=postgres://tvshow:pw@localhost/tvshow_test cargo test --test integration
//!
//! `bootstrap()` runs migrations; `guard()` serializes tests (they share one DB);
//! `clean()` truncates everything so each test starts from a blank slate.

#![allow(dead_code)] // not every test uses every fixture helper

use std::sync::OnceLock;

use backend::{config::Config, state::AppState};
use sqlx::PgPool;
use tokio::sync::{Mutex, MutexGuard};
use uuid::Uuid;

/// Map a small integer to a fixed, deterministic user UUID. Tests refer to users
/// by tiny ids (1, 2, …) for readability; user PKs are now UUIDs, so both the
/// fixtures and the direct backend calls funnel their id through here to agree.
pub fn uid(n: i64) -> Uuid {
    Uuid::from_u128(n as u128)
}

/// Serializes tests within the binary — they all share one database.
static LOCK: OnceLock<Mutex<()>> = OnceLock::new();

pub async fn guard() -> MutexGuard<'static, ()> {
    LOCK.get_or_init(|| Mutex::new(())).lock().await
}

/// Build an `AppState` against the test DB (migrations applied), or `None` when
/// `TEST_DATABASE_URL` is unset — callers then skip.
pub async fn state() -> Option<AppState> {
    // `cargo test` runs with CWD at the package dir (backend/), but .env.local
    // lives at the repo root — try both. An already-set env var still wins.
    let _ = dotenvy::from_filename(".env.local");
    let _ = dotenvy::from_filename("../.env.local");
    let url = std::env::var("TEST_DATABASE_URL").ok()?;
    let config = Config {
        database_url: url,
        catalog_mode: backend::config::CatalogMode::Proxy,
        mirror_scope: backend::config::MirrorScope::OnDemand,
        bind_addr: "127.0.0.1:0".into(),
        thetvdb_base_url: "http://localhost".into(),
        thetvdb_api_key: "test".into(),
        jwt_secret: "test-secret".into(),
        public_base_url: "http://localhost".into(),
        web_base_url: "http://localhost".into(),
        allow_public_registration: false,
        smtp: None,
        s3_endpoint: String::new(),
        s3_region: "garage".into(),
        s3_bucket: "artwork".into(),
        s3_access_key: String::new(),
        s3_secret_key: String::new(),
        sync_interval_secs: None,
        thetvdb_max_rps: 35,
        enrich_interval_secs: None,
        enrich_concurrency: 8,
    };
    Some(AppState::bootstrap(config).await.expect("bootstrap test AppState"))
}

/// Wipe all app + catalog data so each test starts clean.
pub async fn clean(db: &PgPool) {
    sqlx::query(
        "TRUNCATE app.users, app.user_show, app.watch_event, app.episode_rating, \
                  app.episode_rewatch, app.list, app.list_item, \
                  catalog.series, catalog.episode, catalog.season, \
                  catalog.translation, catalog.artwork RESTART IDENTITY CASCADE",
    )
    .execute(db)
    .await
    .expect("truncate");
}

// ---- fixture builders ------------------------------------------------------

pub async fn insert_user(db: &PgPool, id: i64, email: &str) {
    let hash = backend::auth::password::hash("Fixture123!pass").unwrap();
    sqlx::query("INSERT INTO app.users (id, screen_name, email, password_hash) VALUES ($1,$2,$3,$4)")
        .bind(uid(id))
        .bind(format!("user{id}"))
        .bind(email)
        .bind(hash)
        .execute(db)
        .await
        .expect("insert user");
}

/// Insert a mirrored series. `raw` is the JSONB TheTVDB payload — put `genres`,
/// `nextAired`/`lastAired`/`airsTime`, etc. there.
pub async fn insert_series(
    db: &PgPool,
    id: i64,
    name: &str,
    year: Option<i32>,
    runtime: Option<i32>,
    score: Option<f64>,
    original_language: Option<&str>,
    raw: serde_json::Value,
) {
    sqlx::query(
        "INSERT INTO catalog.series (id, name, year, runtime, score, original_language, raw) \
         VALUES ($1,$2,$3,$4,$5,$6,$7)",
    )
    .bind(id)
    .bind(name)
    .bind(year)
    .bind(runtime)
    .bind(score)
    .bind(original_language)
    .bind(raw)
    .execute(db)
    .await
    .expect("insert series");
}

/// Convenience: a series carrying the given genre `{id,name}` pairs in its raw.
pub fn genres_raw(pairs: &[(i64, &str)]) -> serde_json::Value {
    let genres: Vec<_> = pairs
        .iter()
        .map(|(id, name)| serde_json::json!({ "id": id.to_string(), "name": name }))
        .collect();
    serde_json::json!({ "genres": genres })
}

/// Link a series to genres in the normalized facet tables (what search_db filters on).
pub async fn set_genres(db: &PgPool, series_id: i64, genres: &[(i64, &str)]) {
    for (id, name) in genres {
        sqlx::query("INSERT INTO catalog.genre (id, name) VALUES ($1,$2) ON CONFLICT (id) DO NOTHING")
            .bind(id).bind(name).execute(db).await.expect("insert genre");
        sqlx::query("INSERT INTO catalog.series_genre (series_id, genre_id) VALUES ($1,$2) ON CONFLICT DO NOTHING")
            .bind(series_id).bind(id).execute(db).await.expect("insert series_genre");
    }
}

/// Set the non-special episode count on a series (for the "# episodes" filter).
pub async fn set_episode_count(db: &PgPool, series_id: i64, count: i32) {
    sqlx::query("UPDATE catalog.series SET episode_count = $2 WHERE id = $1")
        .bind(series_id).bind(count).execute(db).await.expect("set episode_count");
}

pub async fn follow(db: &PgPool, user_id: i64, series_id: i64, followed: bool, favorited: bool) {
    sqlx::query(
        "INSERT INTO app.user_show (user_id, series_id, is_followed, is_favorited) VALUES ($1,$2,$3,$4)",
    )
    .bind(uid(user_id))
    .bind(series_id)
    .bind(followed)
    .bind(favorited)
    .execute(db)
    .await
    .expect("insert user_show");
}

/// Set arbitrary columns on an existing user_show (status/archived/unavailable/nb).
pub async fn set_user_show(db: &PgPool, user_id: i64, series_id: i64, col: &str, sql_value: &str) {
    // `col` is a fixed identifier chosen by the test author (never user input).
    let q = format!("UPDATE app.user_show SET {col} = {sql_value} WHERE user_id=$1 AND series_id=$2");
    sqlx::query(&q).bind(uid(user_id)).bind(series_id).execute(db).await.expect("update user_show");
}

pub async fn insert_episode(
    db: &PgPool,
    id: i64,
    series_id: i64,
    season: i32,
    number: i32,
    aired: &str,
    name: &str,
) {
    sqlx::query(
        "INSERT INTO catalog.episode (id, series_id, season_number, number, aired, name) \
         VALUES ($1,$2,$3,$4,$5::date,$6)",
    )
    .bind(id)
    .bind(series_id)
    .bind(season)
    .bind(number)
    .bind(aired)
    .bind(name)
    .execute(db)
    .await
    .expect("insert episode");
}

/// Insert an episode aired `days_from_now` relative to today (for calendar windows).
pub async fn insert_episode_in_days(
    db: &PgPool,
    id: i64,
    series_id: i64,
    season: i32,
    number: i32,
    days_from_now: i32,
    name: &str,
) {
    sqlx::query(
        "INSERT INTO catalog.episode (id, series_id, season_number, number, aired, name) \
         VALUES ($1,$2,$3,$4, current_date + make_interval(days => $5::int), $6)",
    )
    .bind(id)
    .bind(series_id)
    .bind(season)
    .bind(number)
    .bind(days_from_now)
    .bind(name)
    .execute(db)
    .await
    .expect("insert episode (relative)");
}

pub async fn watch(db: &PgPool, user_id: i64, series_id: i64, episode_id: i64, source_uuid: &str) {
    watch_ago(db, user_id, series_id, episode_id, source_uuid, 0).await;
}

/// A watch event carrying season/episode numbers (drives the dead-id episode remap).
pub async fn watch_se(
    db: &PgPool,
    user_id: i64,
    series_id: i64,
    episode_id: i64,
    season: i32,
    number: i32,
    source_uuid: &str,
) {
    sqlx::query(
        "INSERT INTO app.watch_event \
           (user_id, entity_type, series_id, episode_id, season_number, episode_number, source_uuid, watched_at) \
         VALUES ($1,'episode',$2,$3,$4,$5,$6, now())",
    )
    .bind(uid(user_id))
    .bind(series_id)
    .bind(episode_id)
    .bind(season)
    .bind(number)
    .bind(source_uuid)
    .execute(db)
    .await
    .expect("insert watch_event w/ s/e");
}

/// Like [`watch`], but `days_ago` in the past (drives the stale/watching split).
pub async fn watch_ago(
    db: &PgPool,
    user_id: i64,
    series_id: i64,
    episode_id: i64,
    source_uuid: &str,
    days_ago: i64,
) {
    sqlx::query(
        "INSERT INTO app.watch_event (user_id, entity_type, series_id, episode_id, source_uuid, watched_at) \
         VALUES ($1,'episode',$2,$3,$4, now() - make_interval(days => $5::int))",
    )
    .bind(uid(user_id))
    .bind(series_id)
    .bind(episode_id)
    .bind(source_uuid)
    .bind(days_ago as i32)
    .execute(db)
    .await
    .expect("insert watch_event");
}
