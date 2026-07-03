use axum::{
    Json,
    extract::{Path, State},
};

use crate::{auth::AuthUser, error::AppResult, state::AppState, tracking, tracking::WatchResult};

/// Mark an episode seen.
pub async fn watch(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(episode_id): Path<i64>,
) -> AppResult<Json<WatchResult>> {
    Ok(Json(tracking::watch_episode(&state, user_id, episode_id).await?))
}

/// Mark an episode unseen (removes its watch history).
pub async fn unwatch(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Path(episode_id): Path<i64>,
) -> AppResult<Json<WatchResult>> {
    Ok(Json(tracking::unwatch_episode(&state, user_id, episode_id).await?))
}
