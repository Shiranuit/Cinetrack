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

/// The user's tracked movies (library Movies section).
pub async fn list_movies(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<LangsQuery>,
) -> AppResult<Json<Vec<LibraryMovie>>> {
    Ok(Json(movies::list(&state, uid, &q.list()).await?))
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
