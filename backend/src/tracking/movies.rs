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
    pub watchlist: bool,       // "watch later"
    pub rating: Option<i16>,   // labeled 1..5 (Hate/Dislike/OK/Like/Love), null = unrated
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct LibraryMovie {
    pub movie_id: i64,
    pub name: Option<String>,
    pub image_url: Option<String>,
    pub year: Option<i32>,
    pub is_favorited: bool,
    pub watched_count: i32,
    pub watchlist: bool,
    pub rating: Option<i16>,
    pub last_watched: Option<i64>,
}

/// The user's relationship to a movie (defaults to "not tracked").
pub async fn relation(state: &AppState, user_id: Uuid, movie_id: i64) -> AppResult<MovieRelation> {
    let row: Option<(bool, bool, i32, bool, Option<i16>)> = sqlx::query_as(
        "SELECT is_favorited, watched, watched_count, watchlist, rating \
         FROM app.user_movie WHERE user_id = $1 AND movie_id = $2",
    )
    .bind(user_id)
    .bind(movie_id)
    .fetch_optional(&state.db)
    .await?;
    let (is_favorited, watched, watched_count, watchlist, rating) = row.unwrap_or((false, false, 0, false, None));
    Ok(MovieRelation { movie_id, is_favorited, watched, watched_count, watchlist, rating })
}

/// Mark a movie watched (each call is one watch; increments the rewatch count).
pub async fn watch(state: &AppState, user_id: Uuid, movie_id: i64) -> AppResult<MovieRelation> {
    // Cache the movie so the library has its name/poster.
    let _ = catalog::movie::get(state, movie_id, Some("eng")).await;

    // Watching a movie also removes it from watch-later — a movie is watched XOR
    // watch-later, never both.
    sqlx::query(
        "INSERT INTO app.user_movie (user_id, movie_id, watched, watched_count, watchlist, last_watched, updated_at) \
         VALUES ($1, $2, true, 1, false, now(), now()) \
         ON CONFLICT (user_id, movie_id) DO UPDATE SET \
           watched = true, watched_count = app.user_movie.watched_count + 1, \
           watchlist = false, last_watched = now(), updated_at = now()",
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

/// Log one movie watch event for history, but only if this movie has none yet — so
/// implicit "marked watched" actions (favorite, rating) keep the watched⇒has-history
/// invariant without piling up phantom watches when re-triggered.
async fn ensure_movie_watch_event(state: &AppState, user_id: Uuid, movie_id: i64) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO app.watch_event (user_id, entity_type, movie_id, source_uuid, watched_at) \
         SELECT $1, 'movie', $2, 'movie-' || $2 || '-' || gen_random_uuid(), now() \
         WHERE NOT EXISTS ( \
           SELECT 1 FROM app.watch_event WHERE user_id = $1 AND movie_id = $2 AND entity_type = 'movie')",
    )
    .bind(user_id)
    .bind(movie_id)
    .execute(&state.db)
    .await?;
    Ok(())
}

pub async fn set_favorite(state: &AppState, user_id: Uuid, movie_id: i64, value: bool) -> AppResult<MovieRelation> {
    let _ = catalog::movie::get(state, movie_id, Some("eng")).await;
    if !value {
        // Un-favoriting only clears the flag; the watched state is left untouched.
        sqlx::query(
            "INSERT INTO app.user_movie (user_id, movie_id, is_favorited, updated_at) \
             VALUES ($1, $2, false, now()) \
             ON CONFLICT (user_id, movie_id) DO UPDATE SET is_favorited = false, updated_at = now()",
        )
        .bind(user_id)
        .bind(movie_id)
        .execute(&state.db)
        .await?;
        return relation(state, user_id, movie_id).await;
    }

    // Favoriting implies you've seen the movie: mark it watched (without bumping the
    // rewatch count if it was already watched), and since a movie is watched XOR
    // watch-later, it leaves watch-later.
    sqlx::query(
        "INSERT INTO app.user_movie \
           (user_id, movie_id, is_favorited, watched, watched_count, watchlist, last_watched, updated_at) \
         VALUES ($1, $2, true, true, 1, false, now(), now()) \
         ON CONFLICT (user_id, movie_id) DO UPDATE SET \
           is_favorited = true, watched = true, \
           watched_count = GREATEST(app.user_movie.watched_count, 1), \
           watchlist = false, \
           last_watched = COALESCE(app.user_movie.last_watched, now()), \
           updated_at = now()",
    )
    .bind(user_id)
    .bind(movie_id)
    .execute(&state.db)
    .await?;

    ensure_movie_watch_event(state, user_id, movie_id).await?;
    relation(state, user_id, movie_id).await
}

/// Set (or clear with `None`) the user's labeled 1..5 rating for a movie. Rating a
/// movie implicitly marks it watched — you rate what you've seen. This is
/// MOVIE-specific: series (`set_show_rating`) must not be forced "watched" by a
/// rating, since a show's watched state is its per-episode progress. Clearing the
/// rating leaves the watched state alone.
pub async fn set_rating(state: &AppState, user_id: Uuid, movie_id: i64, rating: Option<i16>) -> AppResult<MovieRelation> {
    if let Some(r) = rating
        && !(1..=5).contains(&r)
    {
        return Err(crate::error::AppError::BadRequest("rating must be between 1 and 5".into()));
    }
    let _ = catalog::movie::get(state, movie_id, Some("eng")).await;
    let Some(r) = rating else {
        // Clearing the rating only clears the flag; the watched state is left untouched.
        sqlx::query(
            "INSERT INTO app.user_movie (user_id, movie_id, rating, updated_at) \
             VALUES ($1, $2, NULL, now()) \
             ON CONFLICT (user_id, movie_id) DO UPDATE SET rating = NULL, updated_at = now()",
        )
        .bind(user_id)
        .bind(movie_id)
        .execute(&state.db)
        .await?;
        return relation(state, user_id, movie_id).await;
    };

    // Rating implies you've seen the movie: mark it watched (without bumping the
    // rewatch count if it was already watched), and since a movie is watched XOR
    // watch-later, it leaves watch-later.
    sqlx::query(
        "INSERT INTO app.user_movie \
           (user_id, movie_id, rating, watched, watched_count, watchlist, last_watched, updated_at) \
         VALUES ($1, $2, $3, true, 1, false, now(), now()) \
         ON CONFLICT (user_id, movie_id) DO UPDATE SET \
           rating = $3, watched = true, \
           watched_count = GREATEST(app.user_movie.watched_count, 1), \
           watchlist = false, \
           last_watched = COALESCE(app.user_movie.last_watched, now()), \
           updated_at = now()",
    )
    .bind(user_id)
    .bind(movie_id)
    .bind(r)
    .execute(&state.db)
    .await?;

    ensure_movie_watch_event(state, user_id, movie_id).await?;
    relation(state, user_id, movie_id).await
}

/// Add/remove a movie from the "watch later" list (the movie equivalent of a
/// series' `for_later` status).
pub async fn set_watchlist(state: &AppState, user_id: Uuid, movie_id: i64, value: bool) -> AppResult<MovieRelation> {
    let _ = catalog::movie::get(state, movie_id, Some("eng")).await;
    // A movie is watched XOR watch-later: adding an already-watched movie to
    // watch-later is a no-op (removing it, value = false, is always allowed).
    sqlx::query(
        "INSERT INTO app.user_movie (user_id, movie_id, watchlist, updated_at) \
         VALUES ($1, $2, $3, now()) \
         ON CONFLICT (user_id, movie_id) DO UPDATE SET \
           watchlist = CASE WHEN $3 AND app.user_movie.watched THEN app.user_movie.watchlist ELSE $3 END, \
           updated_at = now()",
    )
    .bind(user_id)
    .bind(movie_id)
    .bind(value)
    .execute(&state.db)
    .await?;
    relation(state, user_id, movie_id).await
}

/// The user's tracked movies (watched or favorited), ordered by `sort` to match the
/// series categories (default = newest-watched first). Sorts that don't apply to a
/// movie (rating/seasons/episodes) fall back to recency.
pub async fn list(state: &AppState, user_id: Uuid, langs: &[String], sort: &str, desc: bool) -> AppResult<Vec<LibraryMovie>> {
    // Whitelisted column + direction (never interpolate raw input).
    let dir = if desc { "DESC" } else { "ASC" };
    let col = match sort {
        "name" => "name",
        "year" => "m.year",
        "runtime" => "m.runtime",
        "updated" => "m.last_updated",
        "my_rating" => "um.rating",
        _ => "um.last_watched",
    };
    let order = format!("{col} {dir} NULLS LAST, name NULLS LAST");
    let rows = sqlx::query_as::<_, LibraryMovie>(&format!(
        "SELECT um.movie_id, \
                COALESCE((SELECT tr.name FROM catalog.translation tr \
                          WHERE tr.entity_type = 'movie' AND tr.entity_id = um.movie_id AND tr.name IS NOT NULL \
                            AND tr.language = ANY($2) ORDER BY array_position($2, tr.language) LIMIT 1), m.name) AS name, \
                m.image_url, m.year, um.is_favorited, um.watched_count, um.watchlist, um.rating, \
                extract(epoch FROM um.last_watched)::bigint AS last_watched \
         FROM app.user_movie um \
         LEFT JOIN catalog.movie m ON m.id = um.movie_id \
         WHERE um.user_id = $1 AND (um.watched OR um.is_favorited OR um.watchlist) \
         ORDER BY {order}"
    ))
    .bind(user_id)
    .bind(langs)
    .fetch_all(&state.db)
    .await?;
    Ok(rows)
}
