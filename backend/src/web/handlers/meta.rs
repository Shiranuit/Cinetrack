use axum::{Json, extract::State};
use serde::Serialize;

use crate::state::AppState;

/// Public feature flags the frontend reads (unauthenticated) at startup to tailor
/// the UI — e.g. hiding the "create an account" affordance when self-signup is off.
#[derive(Serialize)]
pub struct ServerConfig {
    /// Whether visitors can self-register WITHOUT an invite. When false, sign-up is
    /// invite-only: the create-account toggle is hidden, but invite deep links still
    /// work (they carry a code straight into the register form).
    registration_enabled: bool,
}

/// `GET /api/config` — server feature flags. No DB access; cheap and public.
pub async fn config(State(state): State<AppState>) -> Json<ServerConfig> {
    Json(ServerConfig {
        registration_enabled: state.config.allow_public_registration,
    })
}
