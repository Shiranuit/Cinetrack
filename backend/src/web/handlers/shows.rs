use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde::Deserialize;
use serde_json::{Value, json};

use crate::{auth::AuthUser, error::AppResult, state::AppState, tracking, web::query::LangsQuery};

/// The authenticated user's tracked shows.
pub async fn list(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<LangsQuery>,
) -> AppResult<Json<Vec<tracking::UserShowRow>>> {
    Ok(Json(tracking::list_shows(&state, user_id, &q.list()).await?))
}

/// Remove a show from the library (tracking + watch history).
pub async fn remove(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
) -> AppResult<Json<Value>> {
    tracking::remove_show(&state, user_id, series_id).await?;
    Ok(Json(json!({ "series_id": series_id, "removed": true })))
}

pub async fn follow(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
) -> AppResult<Json<Value>> {
    tracking::set_followed(&state, user_id, series_id, true).await?;
    Ok(Json(json!({ "series_id": series_id, "is_followed": true })))
}

pub async fn unfollow(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
) -> AppResult<Json<Value>> {
    tracking::set_followed(&state, user_id, series_id, false).await?;
    Ok(Json(json!({ "series_id": series_id, "is_followed": false })))
}

pub async fn favorite(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
) -> AppResult<Json<Value>> {
    tracking::set_favorited(&state, user_id, series_id, true).await?;
    Ok(Json(json!({ "series_id": series_id, "is_favorited": true })))
}

pub async fn unfavorite(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
) -> AppResult<Json<Value>> {
    tracking::set_favorited(&state, user_id, series_id, false).await?;
    Ok(Json(json!({ "series_id": series_id, "is_favorited": false })))
}

#[derive(Deserialize)]
pub struct StatusReq {
    /// "for_later", "stopped", or null to clear.
    pub status: Option<String>,
}

pub async fn set_status(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
    Json(req): Json<StatusReq>,
) -> AppResult<Json<Value>> {
    tracking::set_status(&state, user_id, series_id, req.status.as_deref()).await?;
    Ok(Json(json!({ "series_id": series_id, "status": req.status })))
}

#[derive(Deserialize)]
pub struct RatingReq {
    /// 1..10, or null to clear.
    pub rating: Option<i16>,
}

/// Set/clear the user's rating for a show.
pub async fn set_rating(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
    Json(req): Json<RatingReq>,
) -> AppResult<Json<Value>> {
    tracking::set_show_rating(&state, user_id, series_id, req.rating).await?;
    Ok(Json(json!({ "series_id": series_id, "rating": req.rating })))
}

/// The user's relationship to a single show (flags default to false when untracked).
pub async fn get_one(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
    Query(q): Query<LangsQuery>,
) -> AppResult<Json<Value>> {
    let row = tracking::get_show(&state, user_id, series_id, &q.list()).await?;
    Ok(Json(match row {
        Some(s) => json!({
            "series_id": s.series_id, "is_followed": s.is_followed, "is_favorited": s.is_favorited,
            "status": s.status, "archived": s.archived, "nb_episodes_seen": s.nb_episodes_seen,
            "rating": s.rating,
        }),
        None => json!({
            "series_id": series_id, "is_followed": false, "is_favorited": false,
            "status": null, "archived": false, "nb_episodes_seen": 0, "rating": null,
        }),
    }))
}

/// Per-episode watch counts for a series (episode_id → times watched).
pub async fn seen(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
) -> AppResult<Json<Value>> {
    let counts = tracking::seen_episode_counts(&state, user_id, series_id).await?;
    let map: serde_json::Map<String, Value> = counts
        .into_iter()
        .map(|(id, n)| (id.to_string(), Value::from(n)))
        .collect();
    Ok(Json(json!({ "series_id": series_id, "counts": map })))
}

#[derive(Deserialize)]
pub struct LibraryQuery {
    pub langs: Option<String>,
    /// Orders shows within each category; defaults to recency ("popularity").
    pub sort: Option<String>,
    /// Sort direction: "desc" (default) or "asc".
    pub dir: Option<String>,
}

/// The user's tracked shows grouped into categories (watching / stale / not started / stopped).
pub async fn library(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<LibraryQuery>,
) -> AppResult<Json<tracking::Library>> {
    let langs = LangsQuery { langs: q.langs.clone() }.list();
    let sort = q.sort.as_deref().unwrap_or("popularity");
    let desc = q.dir.as_deref() != Some("asc");
    Ok(Json(tracking::library(&state, user_id, &langs, sort, desc).await?))
}

#[derive(Deserialize)]
pub struct SeasonWatchQuery {
    /// When true, add a watch to EVERY episode (rewatch) instead of only unseen ones.
    pub rewatch: Option<bool>,
}

#[derive(Deserialize)]
pub struct SeasonUnwatchQuery {
    /// When true, remove only the most recent watch of each episode (decrement the
    /// ×N count by one) instead of clearing every watch to zero.
    pub decrement: Option<bool>,
}

/// Mark a whole season watched. `?rewatch=true` bumps every episode's ×N count.
pub async fn watch_season(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path((series_id, season)): Path<(i64, i32)>,
    Query(q): Query<SeasonWatchQuery>,
) -> AppResult<Json<Value>> {
    let nb = if q.rewatch.unwrap_or(false) {
        tracking::rewatch_season(&state, user_id, series_id, season).await?
    } else {
        tracking::watch_season(&state, user_id, series_id, season).await?
    };
    Ok(Json(json!({ "series_id": series_id, "season": season, "nb_episodes_seen": nb })))
}

/// Un-watch a whole season. `?decrement=true` removes only one watch per episode
/// (the inverse of `?rewatch=true`) instead of clearing every watch.
pub async fn unwatch_season(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path((series_id, season)): Path<(i64, i32)>,
    Query(q): Query<SeasonUnwatchQuery>,
) -> AppResult<Json<Value>> {
    let nb = if q.decrement.unwrap_or(false) {
        tracking::decrement_watch_season(&state, user_id, series_id, season).await?
    } else {
        tracking::unwatch_season(&state, user_id, series_id, season).await?
    };
    Ok(Json(json!({ "series_id": series_id, "season": season, "nb_episodes_seen": nb })))
}

/// Mark the WHOLE series watched (all seasons), or rewatch it with `?rewatch=true`.
pub async fn watch_series(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
    Query(q): Query<SeasonWatchQuery>,
) -> AppResult<Json<Value>> {
    let nb = if q.rewatch.unwrap_or(false) {
        tracking::rewatch_series(&state, user_id, series_id).await?
    } else {
        tracking::watch_series(&state, user_id, series_id).await?
    };
    Ok(Json(json!({ "series_id": series_id, "nb_episodes_seen": nb })))
}

/// Un-watch the whole series. `?decrement=true` removes only one watch per episode
/// (the inverse of `?rewatch=true`) instead of clearing every watch.
pub async fn unwatch_series(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(series_id): Path<i64>,
    Query(q): Query<SeasonUnwatchQuery>,
) -> AppResult<Json<Value>> {
    let nb = if q.decrement.unwrap_or(false) {
        tracking::decrement_watch_series(&state, user_id, series_id).await?
    } else {
        tracking::unwatch_series(&state, user_id, series_id).await?
    };
    Ok(Json(json!({ "series_id": series_id, "nb_episodes_seen": nb })))
}
