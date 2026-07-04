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
    /// The backend's running release (e.g. "v0.2.0", or "dev"). Clients compare it to
    /// their own build to detect when they're out of date and prompt the user to update.
    version: String,
    /// The lowest client build allowed (e.g. "v0.2.0"); clients older than this are
    /// hard-blocked with an "update required" screen. Null when no floor is set.
    min_version: Option<String>,
}

/// `GET /api/config` — server feature flags + version. No DB access; cheap and public.
pub async fn config(State(state): State<AppState>) -> Json<ServerConfig> {
    let min = state.config.min_app_version.clone();
    Json(ServerConfig {
        registration_enabled: state.config.allow_public_registration,
        version: state.config.app_version.clone(),
        min_version: (!min.is_empty()).then_some(min),
    })
}
