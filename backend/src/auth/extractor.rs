//! `AuthUser` extractor — validates the `Authorization: Bearer <jwt>` header and
//! yields the authenticated user id. Use it as a handler argument to require auth.

use axum::{
    extract::FromRequestParts,
    http::{header::AUTHORIZATION, request::Parts},
};

use crate::{auth, error::AppError, state::AppState};

pub struct AuthUser(pub i64);

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .ok_or_else(|| AppError::Unauthorized("missing bearer token".into()))?;
        let user_id = auth::token::verify(&state.config.jwt_secret, token)?;

        // Reject tokens whose user no longer exists (e.g. a deleted account whose
        // session is still open) with a clean 401 so the client re-authenticates,
        // instead of letting a later write fail a foreign-key constraint with a 500.
        let exists: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM app.users WHERE id = $1)")
            .bind(user_id)
            .fetch_one(&state.db)
            .await
            .unwrap_or(false);
        if !exists {
            return Err(AppError::Unauthorized("account no longer exists — please sign in again".into()));
        }

        Ok(AuthUser(user_id))
    }
}
