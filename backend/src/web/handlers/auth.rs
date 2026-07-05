use uuid::Uuid;
use std::{sync::OnceLock, time::Duration};

use axum::{
    Json,
    extract::State,
    http::{HeaderMap, header::{COOKIE, SET_COOKIE, USER_AGENT}},
    response::{IntoResponse, Response},
};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::{
    auth,
    auth::{AuthSession, AuthUser, session},
    error::{AppError, AppResult},
    state::AppState,
};

/// Web refresh-token cookie name.
const REFRESH_COOKIE: &str = "cinetrack_refresh";

/// Real client IP from `X-Forwarded-For`. We take the LAST hop — the value set by
/// our own reverse proxy (Caddy) — because earlier entries are client-supplied and
/// forgeable. Using the first entry would let an attacker spoof the header to bypass
/// rate limiting and forge audit IPs.
///
/// Trust chain in production: browser -> Cloudflare -> Caddy -> backend. Caddy
/// OVERWRITES `X-Forwarded-For` with the real visitor IP (from Cloudflare's
/// `CF-Connecting-IP`) and only accepts requests from Cloudflare's edge, so the
/// single value we read here is authoritative. Without Cloudflare, Caddy sets it to
/// the direct peer instead — either way, the last hop is the trusted proxy's value.
pub(crate) fn client_ip(headers: &HeaderMap) -> String {
    headers
        .get("x-forwarded-for")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.rsplit(',').next())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

/// A short device label (User-Agent) for the session list.
fn device(headers: &HeaderMap) -> Option<String> {
    headers.get(USER_AGENT).and_then(|v| v.to_str().ok()).map(|s| s.chars().take(200).collect())
}

/// A fixed valid Argon2 hash, computed once, used to spend equivalent CPU when an
/// email isn't found — so login response time doesn't reveal whether it exists.
fn dummy_hash() -> &'static str {
    static H: OnceLock<String> = OnceLock::new();
    H.get_or_init(|| auth::password::hash("not-a-real-password-timing-equalizer").unwrap())
}

/// Map a unique-constraint violation to a user-facing conflict message.
fn unique_conflict(constraint: Option<&str>) -> AppError {
    match constraint {
        Some("users_screen_name_lower_key") => AppError::Conflict("username already taken".into()),
        _ => AppError::Conflict("email already registered".into()),
    }
}

// ---- session response / cookie helpers -------------------------------------

/// Web clients send `X-Use-Cookie: 1` so the refresh token is returned in an
/// httpOnly cookie (invisible to JS) rather than the response body.
fn wants_cookie(headers: &HeaderMap) -> bool {
    headers
        .get("x-use-cookie")
        .and_then(|v| v.to_str().ok())
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false)
}

fn refresh_cookie(token: &str, secure: bool, max_age: i64) -> String {
    // Scoped to /api/auth so it's only sent to refresh/logout, not every request.
    let mut c = format!("{REFRESH_COOKIE}={token}; HttpOnly; SameSite=Lax; Path=/api/auth; Max-Age={max_age}");
    if secure {
        c.push_str("; Secure");
    }
    c
}

fn read_refresh_cookie(headers: &HeaderMap) -> Option<String> {
    let cookies = headers.get(COOKIE)?.to_str().ok()?;
    for part in cookies.split(';') {
        if let Some(v) = part.trim().strip_prefix(&format!("{REFRESH_COOKIE}=")) {
            return Some(v.to_string());
        }
    }
    None
}

/// Build a login/refresh response. Web (cookie mode) gets the refresh token as an
/// httpOnly cookie and only the access token in the body; mobile/desktop get both
/// in the body (stored in secure storage).
fn auth_response(state: &AppState, headers: &HeaderMap, user_id: Uuid, access: String, refresh: String) -> Response {
    let secure = state.config.public_base_url.starts_with("https");
    let mut body = json!({
        "token": access.clone(),        // alias for compatibility
        "access_token": access,
        "user_id": user_id,
        "expires_in": session::ACCESS_TTL_SECS,
    });
    if wants_cookie(headers) {
        ([(SET_COOKIE, refresh_cookie(&refresh, secure, 30 * 24 * 3600))], Json(body)).into_response()
    } else {
        body["refresh_token"] = json!(refresh);
        Json(body).into_response()
    }
}

#[derive(Deserialize)]
pub struct RegisterReq {
    pub email: String,
    pub password: String,
    pub screen_name: Option<String>,
    pub invite_code: Option<String>,
}

#[derive(Deserialize)]
pub struct LoginReq {
    pub email: String,
    pub password: String,
}

pub async fn register(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<RegisterReq>,
) -> AppResult<Response> {
    if !state.auth_limiter.check(&format!("register:{}", client_ip(&headers)), 10, Duration::from_secs(3600)) {
        return Err(AppError::TooManyRequests("too many sign-up attempts, try again later".into()));
    }

    let email = req.email.trim().to_ascii_lowercase();
    if !email.contains('@') {
        return Err(AppError::BadRequest("invalid email".into()));
    }

    let invite_hash = if state.config.allow_public_registration {
        None
    } else {
        let code = req.invite_code.as_deref().map(str::trim).filter(|s| !s.is_empty())
            .ok_or_else(|| AppError::Forbidden("registration is invite-only".into()))?;
        let h = auth::token_hash(code);
        let valid: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM app.invitation WHERE code_hash = $1 AND used_by IS NULL AND expires_at > now())",
        )
        .bind(&h)
        .fetch_one(&state.db)
        .await?;
        if !valid {
            return Err(AppError::Forbidden("invalid or expired invite".into()));
        }
        Some(h)
    };

    auth::password::validate(&req.password)?;
    let hash = auth::password::hash(&req.password)?;
    let screen_name = req
        .screen_name
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| email.split('@').next().unwrap_or("user"))
        .to_string();

    // UUIDv7: time-ordered (good index locality) yet non-enumerable, and generated
    // here so there's no MAX(id)+1 read-then-insert race on signup.
    let new_id = uuid::Uuid::now_v7();
    let mut tx = state.db.begin().await?;
    let ins = sqlx::query(
        "INSERT INTO app.users (id, email, password_hash, screen_name) VALUES ($1, $2, $3, $4)",
    )
    .bind(new_id)
    .bind(&email)
    .bind(&hash)
    .bind(&screen_name)
    .execute(&mut *tx)
    .await;
    if let Err(sqlx::Error::Database(e)) = &ins {
        if e.is_unique_violation() {
            return Err(unique_conflict(e.constraint()));
        }
    }
    ins?;

    if let Some(h) = &invite_hash {
        let consumed = sqlx::query(
            "UPDATE app.invitation SET used_by = $1, used_at = now() \
             WHERE code_hash = $2 AND used_by IS NULL AND expires_at > now()",
        )
        .bind(new_id)
        .bind(h)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if consumed != 1 {
            return Err(AppError::Forbidden("invalid or expired invite".into()));
        }
    }
    tx.commit().await?;

    crate::audit::record(&state, Some(new_id), crate::audit::event::REGISTERED, &client_ip(&headers),
        Some(json!({ "via_invite": invite_hash.is_some() }))).await;

    let (sid, refresh) = session::create(&state, new_id, device(&headers), &client_ip(&headers)).await?;
    let access = auth::token::issue(&state.config.jwt_secret, new_id, &sid, session::ACCESS_TTL_SECS)?;
    Ok(auth_response(&state, &headers, new_id, access, refresh))
}

pub async fn login(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<LoginReq>,
) -> AppResult<Response> {
    let email = req.email.trim().to_ascii_lowercase();
    let ip = client_ip(&headers);
    let ok_ip = state.auth_limiter.check(&format!("login-ip:{ip}"), 20, Duration::from_secs(300));
    let ok_acct = state.auth_limiter.check(&format!("login-acct:{email}"), 8, Duration::from_secs(900));
    if !ok_ip || !ok_acct {
        return Err(AppError::TooManyRequests("too many login attempts, try again later".into()));
    }

    let row: Option<(Uuid, Option<String>)> =
        sqlx::query_as("SELECT id, password_hash FROM app.users WHERE email = $1")
            .bind(&email)
            .fetch_optional(&state.db)
            .await?;

    let invalid = || AppError::Unauthorized("invalid credentials".into());
    match row {
        Some((user_id, Some(hash))) if auth::password::verify(&req.password, &hash) => {
            state.auth_limiter.reset(&format!("login-acct:{email}"));
            crate::audit::record(&state, Some(user_id), crate::audit::event::LOGIN_OK, &ip, None).await;
            let (sid, refresh) = session::create(&state, user_id, device(&headers), &ip).await?;
            let access = auth::token::issue(&state.config.jwt_secret, user_id, &sid, session::ACCESS_TTL_SECS)?;
            Ok(auth_response(&state, &headers, user_id, access, refresh))
        }
        Some((user_id, Some(_))) => {
            crate::audit::record(&state, Some(user_id), crate::audit::event::LOGIN_FAIL, &ip, None).await;
            Err(invalid())
        }
        _ => {
            let _ = auth::password::verify(&req.password, dummy_hash());
            crate::audit::record(&state, None, crate::audit::event::LOGIN_FAIL, &ip, Some(json!({ "email": email }))).await;
            Err(invalid())
        }
    }
}

#[derive(Deserialize)]
pub struct RefreshReq {
    pub refresh_token: Option<String>,
}

/// Exchange a refresh token (cookie on web, body on mobile) for a fresh access
/// token, rotating the refresh token.
pub async fn refresh(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Option<Json<RefreshReq>>,
) -> AppResult<Response> {
    if !state.auth_limiter.check(&format!("refresh-ip:{}", client_ip(&headers)), 60, Duration::from_secs(300)) {
        return Err(AppError::TooManyRequests("too many refresh attempts, try again later".into()));
    }
    let presented = read_refresh_cookie(&headers)
        .or_else(|| body.and_then(|Json(b)| b.refresh_token))
        .ok_or_else(|| AppError::Unauthorized("no refresh token".into()))?;

    let (user_id, sid, new_refresh) = session::rotate(&state, &presented).await?;
    let access = auth::token::issue(&state.config.jwt_secret, user_id, &sid, session::ACCESS_TTL_SECS)?;
    Ok(auth_response(&state, &headers, user_id, access, new_refresh))
}

/// Log out THIS device: revoke the session that owns the presented refresh token
/// (cookie on web, body on mobile) and clear the web cookie. Works even if the
/// access token has expired — the whole point of a reliable logout.
pub async fn logout(
    State(state): State<AppState>,
    headers: HeaderMap,
    body: Option<Json<RefreshReq>>,
) -> AppResult<Response> {
    if let Some(rt) = read_refresh_cookie(&headers).or_else(|| body.and_then(|Json(b)| b.refresh_token)) {
        session::revoke_by_refresh(&state, &rt).await?;
    }
    let secure = state.config.public_base_url.starts_with("https");
    let cleared = format!(
        "{REFRESH_COOKIE}=; HttpOnly; SameSite=Lax; Path=/api/auth; Max-Age=0{}",
        if secure { "; Secure" } else { "" }
    );
    Ok(([(SET_COOKIE, cleared)], Json(json!({ "ok": true }))).into_response())
}

#[derive(Serialize, sqlx::FromRow)]
pub struct Me {
    pub id: Uuid,
    pub email: Option<String>,
    pub screen_name: String,
    pub bio: Option<String>,
    pub country_code: Option<String>,
    pub avatar_url: Option<String>,
    pub cover_url: Option<String>,
    pub is_private: bool,
    pub profile_blocks: Vec<String>,
    /// Preferred content languages in priority order (synced across the user's devices).
    pub languages: Vec<String>,
}

pub async fn me(AuthUser(user_id): AuthUser, State(state): State<AppState>) -> AppResult<Json<Me>> {
    sqlx::query_as::<_, Me>(
        "SELECT id, email, screen_name, bio, country_code, avatar_url, cover_url, is_private, profile_blocks, languages \
         FROM app.users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?
    .map(Json)
    .ok_or(AppError::NotFound)
}

/// Permanently delete the authenticated user's account and all their data (their
/// sessions cascade-delete via the FK).
pub async fn delete_me(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> AppResult<Json<Value>> {
    crate::audit::record(&state, Some(user_id), crate::audit::event::ACCOUNT_DELETED, &client_ip(&headers), None).await;
    crate::tracking::delete_account(&state, user_id).await?;
    Ok(Json(json!({ "deleted": true })))
}

/// The authenticated user's recent security activity (logins, changes, etc.).
pub async fn security_log(
    AuthUser(user_id): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<Vec<crate::audit::AuditEntry>>> {
    Ok(Json(crate::audit::recent_for_user(&state, user_id, 50).await?))
}

#[derive(Deserialize)]
pub struct UpdatePasswordReq {
    pub current_password: String,
    pub new_password: String,
}

/// Change password: requires the CURRENT password, then revokes every OTHER
/// session (this one stays signed in).
pub async fn update_password(
    AuthSession { user_id, sid }: AuthSession,
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<UpdatePasswordReq>,
) -> AppResult<Json<Value>> {
    let current: Option<String> = sqlx::query_scalar("SELECT password_hash FROM app.users WHERE id = $1")
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?
        .flatten();
    let current = current.ok_or_else(|| AppError::Unauthorized("no password set".into()))?;
    if !auth::password::verify(&req.current_password, &current) {
        return Err(AppError::Unauthorized("current password is incorrect".into()));
    }

    auth::password::validate(&req.new_password)?;
    let hash = auth::password::hash(&req.new_password)?;
    sqlx::query("UPDATE app.users SET password_hash = $2, updated_at = now() WHERE id = $1")
        .bind(user_id)
        .bind(&hash)
        .execute(&state.db)
        .await?;
    session::revoke_all_except(&state, user_id, &sid).await?;

    crate::audit::record(&state, Some(user_id), crate::audit::event::PASSWORD_CHANGED, &client_ip(&headers), None).await;
    Ok(Json(json!({ "updated": true })))
}

#[derive(Deserialize)]
pub struct ForgotReq {
    pub email: String,
}

/// Start a password reset. ALWAYS returns 200 (no account enumeration).
pub async fn forgot_password(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<ForgotReq>,
) -> AppResult<Json<Value>> {
    if !state.auth_limiter.check(&format!("forgot-ip:{}", client_ip(&headers)), 5, Duration::from_secs(900)) {
        return Err(AppError::TooManyRequests("too many reset requests, try again later".into()));
    }
    let email = req.email.trim().to_ascii_lowercase();
    let user: Option<(Uuid,)> = sqlx::query_as("SELECT id FROM app.users WHERE email = $1")
        .bind(&email)
        .fetch_optional(&state.db)
        .await?;

    if let Some((user_id,)) = user {
        let token = auth::random_token();
        let mut tx = state.db.begin().await?;
        // One active reset link per user: supersede any outstanding (unused) token so
        // a new request invalidates the previous link.
        sqlx::query("UPDATE app.password_reset SET used_at = now() WHERE user_id = $1 AND used_at IS NULL")
            .bind(user_id)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            "INSERT INTO app.password_reset (token_hash, user_id, expires_at) \
             VALUES ($1, $2, now() + interval '10 minutes')",
        )
        .bind(auth::token_hash(&token))
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;

        let link = format!("{}/reset-password?token={}", state.config.web_base_url, token);
        let (subject, text, html) = crate::email_templates::reset_password(&link);
        state.mailer.send_html(&email, &subject, &text, &html).await;
        crate::audit::record(&state, Some(user_id), crate::audit::event::RESET_REQUESTED, &client_ip(&headers), None).await;
    }

    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
pub struct ResetReq {
    pub token: String,
    pub new_password: String,
}

/// Complete a password reset: consume the one-time token, set the new password,
/// and revoke ALL sessions (the user signs in fresh).
pub async fn reset_password(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<ResetReq>,
) -> AppResult<Json<Value>> {
    if !state.auth_limiter.check(&format!("reset-ip:{}", client_ip(&headers)), 10, Duration::from_secs(900)) {
        return Err(AppError::TooManyRequests("too many attempts, try again later".into()));
    }
    auth::password::validate(&req.new_password)?;

    let mut tx = state.db.begin().await?;
    let row: Option<(Uuid,)> = sqlx::query_as(
        "UPDATE app.password_reset SET used_at = now() \
         WHERE token_hash = $1 AND used_at IS NULL AND expires_at > now() RETURNING user_id",
    )
    .bind(auth::token_hash(req.token.trim()))
    .fetch_optional(&mut *tx)
    .await?;
    let Some((user_id,)) = row else {
        return Err(AppError::BadRequest("invalid or expired reset token".into()));
    };

    let hash = auth::password::hash(&req.new_password)?;
    sqlx::query("UPDATE app.users SET password_hash = $2, updated_at = now() WHERE id = $1")
        .bind(user_id)
        .bind(&hash)
        .execute(&mut *tx)
        .await?;
    // Kill every session — a reset implies the old credentials may be compromised.
    sqlx::query("UPDATE app.session SET revoked = true WHERE user_id = $1 AND NOT revoked")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    crate::audit::record(&state, Some(user_id), crate::audit::event::RESET_COMPLETED, &client_ip(&headers), None).await;
    Ok(Json(json!({ "ok": true })))
}

#[derive(Deserialize)]
pub struct UpdateProfileReq {
    pub screen_name: Option<String>,
    pub email: Option<String>,
}

/// Update the authenticated user's display name and/or email.
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
        "SELECT id, email, screen_name, bio, country_code, avatar_url, cover_url, is_private, profile_blocks, languages \
         FROM app.users WHERE id = $1",
    )
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?
    .map(Json)
    .ok_or(AppError::NotFound)
}
