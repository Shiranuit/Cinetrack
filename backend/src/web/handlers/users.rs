use uuid::Uuid;
use axum::{
    Json,
    extract::{Path, Query, State},
};
use serde::Deserialize;
use serde_json::{Value, json};

use crate::{auth::AuthUser, error::AppResult, state::AppState, tracking};

#[derive(Deserialize)]
pub struct SearchQuery {
    pub q: String,
}

/// Find users by screen name.
pub async fn search(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Query(q): Query<SearchQuery>,
) -> AppResult<Json<Vec<tracking::UserBrief>>> {
    if q.q.trim().is_empty() {
        return Ok(Json(vec![]));
    }
    Ok(Json(tracking::search_users(&state, me, q.q.trim()).await?))
}

/// Users the authenticated user follows.
pub async fn following(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<Vec<tracking::UserBrief>>> {
    Ok(Json(tracking::following(&state, me).await?))
}

/// Recent watch activity from people the user follows.
pub async fn feed(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<Vec<tracking::FeedItem>>> {
    Ok(Json(tracking::feed(&state, me).await?))
}

/// Follow another user (or request to, if they're private).
pub async fn follow(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
) -> AppResult<Json<Value>> {
    let status = tracking::follow_user(&state, user_id, target_id).await?;
    Ok(Json(json!({ "followee_id": target_id, "status": status })))
}

pub async fn unfollow(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
) -> AppResult<Json<Value>> {
    tracking::unfollow_user(&state, user_id, target_id).await?;
    Ok(Json(json!({ "followee_id": target_id, "status": "none" })))
}

/// A user's public profile (details hidden for private, non-followed users).
pub async fn profile(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
) -> AppResult<Json<tracking::UserProfile>> {
    Ok(Json(tracking::user_profile(&state, me, target_id).await?))
}

/// Another user's tracked shows (empty if their profile isn't visible to you).
pub async fn user_shows(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
    Query(q): Query<crate::web::query::LangsQuery>,
) -> AppResult<Json<Vec<tracking::UserShowRow>>> {
    Ok(Json(tracking::user_shows(&state, me, target_id, &q.list()).await?))
}

/// Another user's categorized library (empty if not visible to you).
pub async fn user_library(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
    Query(q): Query<crate::web::query::LangsQuery>,
) -> AppResult<Json<tracking::Library>> {
    Ok(Json(tracking::user_library(&state, me, target_id, &q.list()).await?))
}

/// Another user's watch statistics (zeroed if not visible to you).
pub async fn user_stats(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
) -> AppResult<Json<tracking::Stats>> {
    if !tracking::profile_visible(&state, me, target_id).await? {
        return Ok(Json(tracking::Stats::default()));
    }
    Ok(Json(tracking::stats(&state, target_id).await?))
}

/// Another user's tracked movies (empty if not visible to you).
pub async fn user_movies(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(target_id): Path<Uuid>,
    Query(q): Query<crate::web::query::LangsQuery>,
) -> AppResult<Json<Vec<crate::tracking::movies::LibraryMovie>>> {
    if !tracking::profile_visible(&state, me, target_id).await? {
        return Ok(Json(vec![]));
    }
    Ok(Json(tracking::movies::list(&state, target_id, &q.list(), "popularity").await?))
}

/// Incoming pending follow requests.
pub async fn requests(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<Vec<tracking::UserBrief>>> {
    Ok(Json(tracking::follow_requests(&state, me).await?))
}

/// People who follow me (accepted).
pub async fn followers(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<Vec<tracking::UserBrief>>> {
    Ok(Json(tracking::followers(&state, me).await?))
}

/// Remove one of my followers.
pub async fn remove_follower(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(follower_id): Path<Uuid>,
) -> AppResult<Json<Value>> {
    tracking::remove_follower(&state, me, follower_id).await?;
    Ok(Json(json!({ "removed": true })))
}

pub async fn accept_request(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(follower_id): Path<Uuid>,
) -> AppResult<Json<Value>> {
    let ok = tracking::accept_request(&state, me, follower_id).await?;
    Ok(Json(json!({ "accepted": ok })))
}

pub async fn reject_request(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(follower_id): Path<Uuid>,
) -> AppResult<Json<Value>> {
    let ok = tracking::reject_request(&state, me, follower_id).await?;
    Ok(Json(json!({ "rejected": ok })))
}

#[derive(Deserialize)]
pub struct PrivacyReq {
    pub is_private: bool,
}

/// Toggle the current user's profile privacy.
pub async fn set_privacy(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<PrivacyReq>,
) -> AppResult<Json<Value>> {
    tracking::set_private(&state, me, req.is_private).await?;
    Ok(Json(json!({ "is_private": req.is_private })))
}

#[derive(Deserialize)]
pub struct ProfileBlocksReq {
    pub blocks: Vec<String>,
}

/// Update the current user's profile showcase layout.
pub async fn set_profile_blocks(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<ProfileBlocksReq>,
) -> AppResult<Json<Value>> {
    tracking::set_profile_blocks(&state, me, &req.blocks).await?;
    Ok(Json(json!({ "blocks": req.blocks })))
}

#[derive(Deserialize)]
pub struct LanguagesReq {
    pub languages: Vec<String>,
}

/// Update the current user's preferred content languages (priority order). Stored on
/// the user so the choice follows them across devices.
pub async fn set_languages(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<LanguagesReq>,
) -> AppResult<Json<Value>> {
    tracking::set_languages(&state, me, &req.languages).await?;
    Ok(Json(json!({ "languages": req.languages })))
}
