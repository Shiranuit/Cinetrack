//! Per-user movie tracking (watched / favorite / library), mirroring the series
//! tracking in the parent module.

use uuid::Uuid;

use crate::{catalog, error::AppResult, state::AppState};

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct MovieRelation {
    pub movie_id: i64,
    pub is_favorited: bool,
    pub watched: bool,
    pub watched_count: i32,
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct LibraryMovie {
    pub movie_id: i64,
    pub name: Option<String>,
    pub image_url: Option<String>,
    pub year: Option<i32>,
    pub is_favorited: bool,
    pub watched_count: i32,
    pub last_watched: Option<i64>,
}

/// The user's relationship to a movie (defaults to "not tracked").
pub async fn relation(state: &AppState, user_id: Uuid, movie_id: i64) -> AppResult<MovieRelation> {
    let row: Option<(bool, bool, i32)> = sqlx::query_as(
        "SELECT is_favorited, watched, watched_count FROM app.user_movie WHERE user_id = $1 AND movie_id = $2",
    )
    .bind(user_id)
    .bind(movie_id)
    .fetch_optional(&state.db)
    .await?;
    let (is_favorited, watched, watched_count) = row.unwrap_or((false, false, 0));
    Ok(MovieRelation { movie_id, is_favorited, watched, watched_count })
}

/// Mark a movie watched (each call is one watch; increments the rewatch count).
pub async fn watch(state: &AppState, user_id: Uuid, movie_id: i64) -> AppResult<MovieRelation> {
    // Cache the movie so the library has its name/poster.
    let _ = catalog::movie::get(state, movie_id, Some("eng")).await;

    sqlx::query(
        "INSERT INTO app.user_movie (user_id, movie_id, watched, watched_count, last_watched, updated_at) \
         VALUES ($1, $2, true, 1, now(), now()) \
         ON CONFLICT (user_id, movie_id) DO UPDATE SET \
           watched = true, watched_count = app.user_movie.watched_count + 1, last_watched = now(), updated_at = now()",
    )
    .bind(user_id)
    .bind(movie_id)
    .execute(&state.db)
    .await?;

    // Also record in the shared watch history (random uuid → each watch is unique,
    // so rapid rewatches in the same second don't collide).
    sqlx::query(
        "INSERT INTO app.watch_event (user_id, entity_type, movie_id, source_uuid, watched_at) \
         VALUES ($1, 'movie', $2, 'movie-' || $2 || '-' || gen_random_uuid(), now())",
    )
    .bind(user_id)
    .bind(movie_id)
    .execute(&state.db)
    .await?;

    relation(state, user_id, movie_id).await
}

/// Undo one watch (decrements; hitting zero un-marks watched).
pub async fn unwatch(state: &AppState, user_id: Uuid, movie_id: i64) -> AppResult<MovieRelation> {
    sqlx::query(
        "UPDATE app.user_movie SET \
           watched_count = GREATEST(watched_count - 1, 0), \
           watched = (watched_count - 1) > 0, updated_at = now() \
         WHERE user_id = $1 AND movie_id = $2",
    )
    .bind(user_id)
    .bind(movie_id)
    .execute(&state.db)
    .await?;
    relation(state, user_id, movie_id).await
}

pub async fn set_favorite(state: &AppState, user_id: Uuid, movie_id: i64, value: bool) -> AppResult<MovieRelation> {
    let _ = catalog::movie::get(state, movie_id, Some("eng")).await;
    sqlx::query(
        "INSERT INTO app.user_movie (user_id, movie_id, is_favorited, updated_at) \
         VALUES ($1, $2, $3, now()) \
         ON CONFLICT (user_id, movie_id) DO UPDATE SET is_favorited = $3, updated_at = now()",
    )
    .bind(user_id)
    .bind(movie_id)
    .bind(value)
    .execute(&state.db)
    .await?;
    relation(state, user_id, movie_id).await
}

/// The user's tracked movies (watched or favorited), newest-watched first.
pub async fn list(state: &AppState, user_id: Uuid, langs: &[String]) -> AppResult<Vec<LibraryMovie>> {
    let rows = sqlx::query_as::<_, LibraryMovie>(
        "SELECT um.movie_id, \
                COALESCE((SELECT tr.name FROM catalog.translation tr \
                          WHERE tr.entity_type = 'movie' AND tr.entity_id = um.movie_id AND tr.name IS NOT NULL \
                            AND tr.language = ANY($2) ORDER BY array_position($2, tr.language) LIMIT 1), m.name) AS name, \
                m.image_url, m.year, um.is_favorited, um.watched_count, \
                extract(epoch FROM um.last_watched)::bigint AS last_watched \
         FROM app.user_movie um \
         LEFT JOIN catalog.movie m ON m.id = um.movie_id \
         WHERE um.user_id = $1 AND (um.watched OR um.is_favorited) \
         ORDER BY um.last_watched DESC NULLS LAST, name NULLS LAST",
    )
    .bind(user_id)
    .bind(langs)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}
