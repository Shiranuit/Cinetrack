//! Auth extractors — validate the `Authorization: Bearer <access-jwt>` header,
//! confirm the session is still active, and yield the user id (and, for handlers
//! that manage sessions, the session id).

use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts},
};

use crate::{auth, error::AppError, state::AppState};

/// `(user_id, session_id)` for a valid access token whose session is still active.
async fn authenticate(parts: &Parts, state: &AppState) -> Result<(i64, String), AppError> {
    let token = parts
        .headers
        .get(AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .ok_or_else(|| AppError::Unauthorized("missing bearer token".into()))?;
    let (user_id, sid) = auth::token::verify(&state.config.jwt_secret, token)?;
    // Session gone (revoked / expired / account deleted → cascade) means the
    // token is no longer usable, even if the JWT itself hasn't expired.
    if auth::session::is_active(state, &sid).await.unwrap_or(false) {
        Ok((user_id, sid))
    } else {
        Err(AppError::Unauthorized("session expired — please sign in again".into()))
    }
}

/// Require authentication; yields the user id.
pub struct AuthUser(pub i64);

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let (user_id, _sid) = authenticate(parts, state).await?;
        Ok(AuthUser(user_id))
    }
}

/// Like [`AuthUser`] but also yields the session id, for handlers that manage the
/// session itself (logout, password change).
pub struct AuthSession {
    pub user_id: i64,
    pub sid: String,
}

impl FromRequestParts<AppState> for AuthSession {
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let (user_id, sid) = authenticate(parts, state).await?;
        Ok(AuthSession { user_id, sid })
    }
}
