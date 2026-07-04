use axum::{Json, extract::State, http::HeaderMap};
use serde::{Deserialize, Serialize};

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
    /// The one-time code — shown ONCE (we only store its hash). Embedded in `link`.
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
    let expires_at: String = sqlx::query_scalar(&format!(
        "INSERT INTO app.invitation (code_hash, created_by, email, expires_at) \
         VALUES ($1, $2, $3, now() + interval '{INVITE_TTL}') RETURNING expires_at::text",
    ))
    .bind(auth::token_hash(&code))
    .bind(me)
    .bind(&email)
    .fetch_one(&state.db)
    .await?;

    let link = format!("{}/signup?invite={}", state.config.web_base_url, code);

    let emailed = if let Some(to) = &email {
        let body = format!(
            "You've been invited to Cinetrack.\n\n\
             Create your account here (valid 14 days):\n{link}\n\n\
             If you weren't expecting this, you can ignore it."
        );
        state.mailer.send(to, "Your Cinetrack invitation", &body).await;
        true
    } else {
        false
    };

    crate::audit::record(
        &state,
        Some(me),
        crate::audit::event::INVITE_CREATED,
        &client_ip(&headers),
        Some(serde_json::json!({ "emailed": emailed })),
    )
    .await;
    Ok(Json(CreateInviteResp { code, link, expires_at, emailed }))
}

#[derive(Serialize, sqlx::FromRow)]
pub struct InviteRow {
    pub email: Option<String>,
    pub created_at: String,
    pub expires_at: String,
    pub used: bool,
}

/// List my invitations and their status (never reveals the code — only the hash
/// is stored, so the code is shown once at creation).
pub async fn list_invites(
    AuthUser(me): AuthUser,
    State(state): State<AppState>,
) -> AppResult<Json<Vec<InviteRow>>> {
    let rows = sqlx::query_as::<_, InviteRow>(
        "SELECT email, created_at::text, expires_at::text, (used_by IS NOT NULL) AS used \
         FROM app.invitation WHERE created_by = $1 ORDER BY created_at DESC",
    )
    .bind(me)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}
