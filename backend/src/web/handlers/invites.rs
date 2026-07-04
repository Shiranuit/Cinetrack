use axum::{Json, extract::{Path, State}, http::HeaderMap};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::{auth, auth::AuthUser, error::{AppError, AppResult}, state::AppState};

use super::auth::client_ip;

/// How long an unused invite stays valid.
const INVITE_TTL: &str = "14 days";
/// Cap on a single user's outstanding (unused, unexpired) invites, to bound abuse.
const MAX_ACTIVE_INVITES: i64 = 20;

#[derive(Deserialize)]
pub struct CreateInviteReq {
    /// If set, the invite is emailed to this address. Otherwise you get a link to
    /// share manually.
    pub email: Option<String>,
}

#[derive(Serialize)]
pub struct CreateInviteResp {
    pub id: Uuid,
    /// The one-time code, embedded in `link`.
    pub code: String,
    pub link: String,
    pub expires_at: String,
    pub emailed: bool,
}

/// Create a one-time invitation. Returns a shareable link; optionally emails it.
pub async fn create_invite(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(req): Json<CreateInviteReq>,
) -> AppResult<Json<CreateInviteResp>> {
    let active: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM app.invitation WHERE created_by = $1 AND used_by IS NULL AND expires_at > now()",
    )
    .bind(me)
    .fetch_one(&state.db)
    .await?;
    if active >= MAX_ACTIVE_INVITES {
        return Err(AppError::Forbidden(format!(
            "invite limit reached ({MAX_ACTIVE_INVITES} outstanding) — wait for some to be used or expire"
        )));
    }

    let email = req
        .email
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_ascii_lowercase);
    if let Some(e) = &email {
        if !e.contains('@') {
            return Err(AppError::BadRequest("invalid email".into()));
        }
    }

    let code = auth::random_token();
    // Store the plaintext `code` (so the link can be copied later) alongside its
    // hash (the source of truth validated at sign-up). Invites are single-use and
    // low-sensitivity, so keeping the code is an acceptable tradeoff.
    let (id, expires_at): (Uuid, String) = sqlx::query_as(&format!(
        "INSERT INTO app.invitation (code_hash, code, created_by, email, expires_at) \
         VALUES ($1, $2, $3, $4, now() + interval '{INVITE_TTL}') RETURNING id, expires_at::text",
    ))
    .bind(auth::token_hash(&code))
    .bind(&code)
    .bind(me)
    .bind(&email)
    .fetch_one(&state.db)
    .await?;

    let link = format!("{}/signup?invite={}", state.config.web_base_url, code);

    let emailed = if let Some(to) = &email {
        let (subject, text, html) = crate::email_templates::invite(&link);
        state.mailer.send_html(to, &subject, &text, &html).await;
        true
    } else {
        false
    };

    crate::audit::record(
        &state,
        Some(me),
        crate::audit::event::INVITE_CREATED,
        &client_ip(&headers),
        Some(json!({ "emailed": emailed })),
    )
    .await;
    Ok(Json(CreateInviteResp { id, code, link, expires_at, emailed }))
}

#[derive(Serialize)]
pub struct InviteInfo {
    pub id: Uuid,
    pub email: Option<String>,
    pub created_at: String,
    pub expires_at: String,
    pub used: bool,
    /// Full sign-up link — present only for pending (unused, unexpired) invites that
    /// still have a stored code; `None` for used/expired/legacy invites.
    pub link: Option<String>,
}

/// List my invitations and their status, with a copyable link for pending ones.
pub async fn list_invites(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<Vec<InviteInfo>>> {
    let rows: Vec<(Uuid, Option<String>, String, String, bool, Option<String>, bool)> =
        sqlx::query_as(
            "SELECT id, email, created_at::text, expires_at::text, \
                    (used_by IS NOT NULL) AS used, code, (expires_at > now()) AS active \
             FROM app.invitation WHERE created_by = $1 ORDER BY created_at DESC",
        )
        .bind(me)
        .fetch_all(&state.db)
        .await?;

    let base = &state.config.web_base_url;
    let list = rows
        .into_iter()
        .map(|(id, email, created_at, expires_at, used, code, active)| {
            let link = (!used && active)
                .then(|| code.map(|c| format!("{base}/signup?invite={c}")))
                .flatten();
            InviteInfo { id, email, created_at, expires_at, used, link }
        })
        .collect();
    Ok(Json(list))
}

/// Revoke a pending invitation. Refuses once it's been accepted (`used_by` set) —
/// at that point the account already exists, so it's too late to take it back.
pub async fn revoke_invite(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Value>> {
    let affected = sqlx::query(
        "DELETE FROM app.invitation WHERE id = $1 AND created_by = $2 AND used_by IS NULL",
    )
    .bind(id)
    .bind(me)
    .execute(&state.db)
    .await?
    .rows_affected();
    if affected == 0 {
        // Not found, not yours, or already accepted — nothing to revoke.
        return Err(AppError::NotFound);
    }
    Ok(Json(json!({ "revoked": true })))
}
