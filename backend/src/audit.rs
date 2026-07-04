//! Security audit trail. `record` is best-effort — a failed insert is logged but
//! never fails the request it's recording (auditing must not break auth).

use serde_json::Value;

use crate::{error::AppResult, state::AppState};

/// Canonical event names (kept as constants so call sites can't typo them).
pub mod event {
    pub const REGISTERED: &str = "user.registered";
    pub const LOGIN_OK: &str = "login.success";
    pub const LOGIN_FAIL: &str = "login.failed";
    pub const PASSWORD_CHANGED: &str = "password.changed";
    pub const RESET_REQUESTED: &str = "password.reset_requested";
    pub const RESET_COMPLETED: &str = "password.reset_completed";
    pub const INVITE_CREATED: &str = "invite.created";
    pub const ACCOUNT_DELETED: &str = "account.deleted";
}

/// Append one event. `user_id` is `None` for events not tied to a known account
/// (e.g. a login attempt for an unknown email).
pub async fn record(state: &AppState, user_id: Option<i64>, event: &str, ip: &str, detail: Option<Value>) {
    let res = sqlx::query("INSERT INTO app.audit_log (user_id, event, ip, detail) VALUES ($1, $2, $3, $4)")
        .bind(user_id)
        .bind(event)
        .bind(ip)
        .bind(detail)
        .execute(&state.db)
        .await;
    if let Err(e) = res {
        tracing::warn!("audit: failed to record {event}: {e}");
    }
}

#[derive(serde::Serialize, sqlx::FromRow)]
pub struct AuditEntry {
    pub event: String,
    pub ip: Option<String>,
    pub detail: Option<Value>,
    pub created_at: String,
}

/// A user's recent security activity (for the account "security log" screen).
pub async fn recent_for_user(state: &AppState, user_id: i64, limit: i64) -> AppResult<Vec<AuditEntry>> {
    Ok(sqlx::query_as::<_, AuditEntry>(
        "SELECT event, ip, detail, created_at::text FROM app.audit_log \
         WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2",
    )
    .bind(user_id)
    .bind(limit)
    .fetch_all(&state.db)
    .await?)
}
