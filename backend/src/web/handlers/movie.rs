use axum::{
    Json,
    extract::{Path, Query, State},
};

use crate::{
    auth::AuthUser,
    catalog::{self, models::MovieRow},
    error::AppResult,
    state::AppState,
    tracking::movies::{self, LibraryMovie, MovieRelation},
    web::query::{LangQuery, LangsQuery},
};

pub async fn get_movie(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    Query(q): Query<LangQuery>,
) -> AppResult<Json<MovieRow>> {
    Ok(Json(catalog::movie::get(&state, id, q.resolve().as_deref()).await?))
}

#[derive(serde::Deserialize)]
pub struct MoviesQuery {
    pub langs: Option<String>,
    /// Orders the movies list; defaults to recency ("popularity").
    pub sort: Option<String>,
    /// Sort direction: "desc" (default) or "asc".
    pub dir: Option<String>,
}

/// All artworks (posters, backgrounds, ...) for a movie, best-scored first.
pub async fn list_artworks(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<Vec<catalog::models::ArtworkRow>>> {
    catalog::movie::get(&state, id, None).await?;
    Ok(Json(catalog::artwork::list_for_entity(&state, "movie", id).await?))
}

/// The user's tracked movies (library Movies section).
pub async fn list_movies(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<MoviesQuery>,
) -> AppResult<Json<Vec<LibraryMovie>>> {
    let langs = LangsQuery { langs: q.langs.clone() }.list();
    let sort = q.sort.as_deref().unwrap_or("popularity");
    let desc = q.dir.as_deref() != Some("asc");
    Ok(Json(movies::list(&state, uid, &langs, sort, desc).await?))
}

/// The authenticated user's relationship to a movie (watched/favorite/count).
pub async fn movie_relation(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<MovieRelation>> {
    Ok(Json(movies::relation(&state, uid, id).await?))
}

pub async fn watch_movie(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<MovieRelation>> {
    Ok(Json(movies::watch(&state, uid, id).await?))
}

pub async fn unwatch_movie(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<MovieRelation>> {
    Ok(Json(movies::unwatch(&state, uid, id).await?))
}

pub async fn favorite_movie(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<MovieRelation>> {
    Ok(Json(movies::set_favorite(&state, uid, id, true).await?))
}

pub async fn unfavorite_movie(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<MovieRelation>> {
    Ok(Json(movies::set_favorite(&state, uid, id, false).await?))
}

pub async fn watchlist_movie(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<MovieRelation>> {
    Ok(Json(movies::set_watchlist(&state, uid, id, true).await?))
}

pub async fn unwatchlist_movie(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<MovieRelation>> {
    Ok(Json(movies::set_watchlist(&state, uid, id, false).await?))
}

#[derive(serde::Deserialize)]
pub struct RatingReq {
    /// Labeled 1..5, or null to clear.
    pub rating: Option<i16>,
}

/// Set/clear the user's rating for a movie.
pub async fn rate_movie(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
    Json(req): Json<RatingReq>,
) -> AppResult<Json<MovieRelation>> {
    Ok(Json(movies::set_rating(&state, uid, id, req.rating).await?))
}
