use axum::{Json, extract::State};
use serde::{Deserialize, Serialize};

use crate::{auth, auth::AuthUser, error::{AppError, AppResult}, state::AppState};

/// Map a unique-constraint violation to a user-facing conflict message based on
/// which constraint tripped (email vs. username).
fn unique_conflict(constraint: Option<&str>) -> AppError {
    match constraint {
        Some("users_screen_name_lower_key") => AppError::Conflict("username already taken".into()),
        _ => AppError::Conflict("email already registered".into()),
    }
}

#[derive(Deserialize)]
pub struct RegisterReq {
    pub email: String,
    pub password: String,
    pub screen_name: Option<String>,
}

#[derive(Deserialize)]
pub struct LoginReq {
    pub email: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AuthResp {
    pub token: String,
    pub user_id: i64,
}

pub async fn register(
    State(state): State<AppState>,
    Json(req): Json<RegisterReq>,
) -> AppResult<Json<AuthResp>> {
    let email = req.email.trim().to_ascii_lowercase();
    if !email.contains('@') {
        return Err(AppError::BadRequest("invalid email".into()));
    }
    auth::password::validate(&req.password)?;
    let hash = auth::password::hash(&req.password)?;
    let screen_name = req
        .screen_name
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| email.split('@').next().unwrap_or("user"))
        .to_string();

    let new_id: i64 = sqlx::query_scalar("SELECT COALESCE(MAX(id), 0) + 1 FROM app.users")
        .fetch_one(&state.db)
        .await?;

    let result = sqlx::query(
        "INSERT INTO app.users (id, email, password_hash, screen_name) VALUES ($1, $2, $3, $4)",
    )
    .bind(new_id)
    .bind(&email)
    .bind(&hash)
    .bind(&screen_name)
    .execute(&state.db)
    .await;

    if let Err(sqlx::Error::Database(e)) = &result {
        if e.is_unique_violation() {
            return Err(unique_conflict(e.constraint()));
        }
    }
    result?;

    let token = auth::token::issue(&state.config.jwt_secret, new_id)?;
    Ok(Json(AuthResp { token, user_id: new_id }))
}

pub async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginReq>,
) -> AppResult<Json<AuthResp>> {
    let email = req.email.trim().to_ascii_lowercase();
    let row: Option<(i64, Option<String>)> =
        sqlx::query_as("SELECT id, password_hash FROM app.users WHERE email = $1")
            .bind(&email)
            .fetch_optional(&state.db)
            .await?;

    let invalid = || AppError::Unauthorized("invalid credentials".into());
    let (user_id, hash) = row.ok_or_else(invalid)?;
    let hash = hash.ok_or_else(invalid)?;
    if !auth::password::verify(&req.password, &hash) {
        return Err(invalid());
    }

    let token = auth::token::issue(&state.config.jwt_secret, user_id)?;
    Ok(Json(AuthResp { token, user_id }))
}

#[derive(Serialize, sqlx::FromRow)]
pub struct Me {
    pub id: i64,
    pub email: Option<String>,
    pub screen_name: String,
    pub bio: Option<String>,
    pub country_code: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_url: Option<String>,
    pub is_private: bool,
    pub profile_blocks: Vec<String>,
}

pub async fn me(AuthUser(user_id): AuthUser, State(state): State<AppState>) -> AppResult<Json<Me>> {
    sqlx::query_as::<_, Me>(
        "SELECT id, email, screen_name, bio, country_code, avatar_url, cover_url, is_private, profile_blocks \
         FROM app.users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?
    .map(Json)
    .ok_or(AppError::NotFound)
}

/// Permanently delete the authenticated user's account and all their data.
pub async fn delete_me(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<serde_json::Value>> {
    crate::tracking::delete_account(&state, user_id).await?;
    Ok(Json(serde_json::json!({ "deleted": true })))
}

#[derive(Deserialize)]
pub struct UpdatePasswordReq {
    pub new_password: String,
}

/// Change the authenticated user's password. We intentionally do NOT require the
/// current password: there's no password-recovery flow, so an already-signed-in
/// user must be able to reset it. The new password still meets the full policy.
pub async fn update_password(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<UpdatePasswordReq>,
) -> AppResult<Json<serde_json::Value>> {
    auth::password::validate(&req.new_password)?;
    let hash = auth::password::hash(&req.new_password)?;
    sqlx::query("UPDATE app.users SET password_hash = $2, updated_at = now() WHERE id = $1")
        .bind(user_id)
        .bind(&hash)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "updated": true })))
}

#[derive(Deserialize)]
pub struct UpdateProfileReq {
    pub screen_name: Option<String>,
    pub email: Option<String>,
}

/// Update the authenticated user's display name and/or email. Only the provided
/// fields change (others are left untouched via COALESCE).
pub async fn update_profile(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    Json(req): Json<UpdateProfileReq>,
) -> AppResult<Json<Me>> {
    let screen_name = req
        .screen_name
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    let email = match req.email.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
        Some(e) => {
            let e = e.to_ascii_lowercase();
            if !e.contains('@') {
                return Err(AppError::BadRequest("invalid email".into()));
            }
            Some(e)
        }
        None => None,
    };

    let result = sqlx::query(
        "UPDATE app.users SET screen_name = COALESCE($2, screen_name), \
                email = COALESCE($3, email), updated_at = now() WHERE id = $1",
    )
    .bind(user_id)
    .bind(&screen_name)
    .bind(&email)
    .execute(&state.db)
    .await;

    if let Err(sqlx::Error::Database(e)) = &result {
        if e.is_unique_violation() {
            return Err(unique_conflict(e.constraint()));
        }
    }
    result?;

    sqlx::query_as::<_, Me>(
        "SELECT id, email, screen_name, bio, country_code, avatar_url, cover_url, is_private, profile_blocks \
         FROM app.users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?
    .map(Json)
    .ok_or(AppError::NotFound)
}
