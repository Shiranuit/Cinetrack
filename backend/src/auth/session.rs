//! Refresh-token sessions (migrations/0024). Access tokens are short-lived JWTs
//! carrying the session id (`sid`); the long-lived refresh token lives here,
//! hashed, and rotates on every refresh. Presenting an already-rotated token
//! (theft) revokes the whole session.

use uuid::Uuid;

use crate::{auth, error::{AppError, AppResult}, state::AppState};

/// Access-token lifetime. Short — the refresh token (cookie/secure storage)
/// provides session persistence.
pub const ACCESS_TTL_SECS: i64 = 30 * 60;
/// Refresh/session lifetime.
const SESSION_TTL: &str = "30 days";

/// Open a new session for `user_id`. Returns `(session_id, refresh_token)`.
pub async fn create(state: &AppState, user_id: Uuid, device: Option<String>, ip: &str) -> AppResult<(String, String)> {
    let refresh = auth::random_token();
    let sid: String = sqlx::query_scalar(&format!(
        "INSERT INTO app.session (user_id, refresh_hash, device, ip, expires_at) \
         VALUES ($1, $2, $3, $4, now() + interval '{SESSION_TTL}') RETURNING id::text",
    ))
    .bind(user_id)
    .bind(auth::token_hash(&refresh))
    .bind(device)
    .bind(ip)
    .fetch_one(&state.db)
    .await?;
    Ok((sid, refresh))
}

/// Is this session still usable (exists, not revoked, not expired)? Checked on
/// every authenticated request, so revocation (logout / password change) takes
/// effect immediately.
pub async fn is_active(state: &AppState, sid: &str) -> AppResult<bool> {
    // Guard the ::uuid cast so a malformed sid is a clean "inactive", not a 500.
    if uuid::Uuid::parse_str(sid).is_err() {
        return Ok(false);
    }
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM app.session WHERE id = $1::uuid AND NOT revoked AND expires_at > now())",
    )
    .bind(sid)
    .fetch_one(&state.db)
    .await?;
    Ok(ok)
}

/// Revoke the session that owns this refresh token (current or previous). Used by
/// logout, so it works even when the caller's access token has already expired.
pub async fn revoke_by_refresh(state: &AppState, presented: &str) -> AppResult<()> {
    let h = auth::token_hash(presented);
    sqlx::query("UPDATE app.session SET revoked = true WHERE refresh_hash = $1 OR prev_hash = $1")
        .bind(&h)
        .execute(&state.db)
        .await?;
    Ok(())
}

/// Exchange a refresh token for a fresh one (rotation). Returns
/// `(user_id, session_id, new_refresh)`. Reusing an already-rotated token is
/// treated as theft — the session is revoked and an error returned.
pub async fn rotate(state: &AppState, presented: &str) -> AppResult<(Uuid, String, String)> {
    let h = auth::token_hash(presented);
    let row: Option<(String, Uuid, bool)> = sqlx::query_as(
        "SELECT id::text, user_id, (refresh_hash = $1) AS is_current \
         FROM app.session \
         WHERE (refresh_hash = $1 OR prev_hash = $1) AND NOT revoked AND expires_at > now()",
    )
    .bind(&h)
    .fetch_optional(&state.db)
    .await?;

    let Some((sid, user_id, is_current)) = row else {
        return Err(AppError::Unauthorized("invalid refresh token".into()));
    };
    if !is_current {
        // A previous token was replayed — revoke the session (possible theft).
        sqlx::query("UPDATE app.session SET revoked = true WHERE id = $1::uuid")
            .bind(&sid)
            .execute(&state.db)
            .await?;
        return Err(AppError::Unauthorized("refresh token reuse detected — session revoked".into()));
    }

    let new_refresh = auth::random_token();
    sqlx::query(
        "UPDATE app.session SET prev_hash = refresh_hash, refresh_hash = $2, last_used_at = now() \
         WHERE id = $1::uuid",
    )
    .bind(&sid)
    .bind(auth::token_hash(&new_refresh))
    .execute(&state.db)
    .await?;
    Ok((user_id, sid, new_refresh))
}

/// Revoke one session (logout this device).
pub async fn revoke(state: &AppState, sid: &str) -> AppResult<()> {
    sqlx::query("UPDATE app.session SET revoked = true WHERE id = $1::uuid")
        .bind(sid)
        .execute(&state.db)
        .await?;
    Ok(())
}

/// Revoke every session for a user (e.g. after a password reset).
pub async fn revoke_all(state: &AppState, user_id: Uuid) -> AppResult<()> {
    sqlx::query("UPDATE app.session SET revoked = true WHERE user_id = $1 AND NOT revoked")
        .bind(user_id)
        .execute(&state.db)
        .await?;
    Ok(())
}

/// Revoke every session for a user EXCEPT `keep_sid` (e.g. after a password change
/// while staying logged in on this device).
pub async fn revoke_all_except(state: &AppState, user_id: Uuid, keep_sid: &str) -> AppResult<()> {
    sqlx::query("UPDATE app.session SET revoked = true WHERE user_id = $1 AND id <> $2::uuid AND NOT revoked")
        .bind(user_id)
        .bind(keep_sid)
        .execute(&state.db)
        .await?;
    Ok(())
}
