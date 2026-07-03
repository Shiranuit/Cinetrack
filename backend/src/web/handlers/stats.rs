use axum::{Json, extract::State};

use crate::{auth::AuthUser, error::AppResult, state::AppState, tracking};

/// Aggregate watch stats for the authenticated user.
pub async fn get_stats(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<tracking::Stats>> {
    Ok(Json(tracking::stats(&state, user_id).await?))
}
