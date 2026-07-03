use axum::{Json, extract::State};
use serde_json::{Value, json};

use crate::{error::AppResult, state::AppState};

/// Liveness + DB connectivity check.
pub async fn health(State(state): State<AppState>) -> AppResult<Json<Value>> {
    sqlx::query("SELECT 1").execute(&state.db).await?;
    Ok(Json(json!({ "status": "ok" })))
}
