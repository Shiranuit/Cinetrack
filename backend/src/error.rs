use axum::{
    Json,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use serde_json::json;

pub type AppResult<T> = Result<T, AppError>;

#[derive(Debug, thiserror::Error)]
pub enum AppError {
    #[error("not found")]
    NotFound,
    #[error("unauthorized: {0}")]
    Unauthorized(String),
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("conflict: {0}")]
    Conflict(String),
    #[error("database error: {0}")]
    Db(#[from] sqlx::Error),
    #[error("thetvdb error: {0}")]
    TheTvdb(String),
    #[error("storage error: {0}")]
    Storage(String),
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, msg) = match &self {
            AppError::NotFound => (StatusCode::NOT_FOUND, "not found".to_string()),
            AppError::Unauthorized(m) => (StatusCode::UNAUTHORIZED, m.clone()),
            AppError::BadRequest(m) => (StatusCode::BAD_REQUEST, m.clone()),
            AppError::Conflict(m) => (StatusCode::CONFLICT, m.clone()),
            AppError::Db(_) => (StatusCode::INTERNAL_SERVER_ERROR, "database error".to_string()),
            AppError::TheTvdb(m) => (StatusCode::BAD_GATEWAY, m.clone()),
            AppError::Storage(_) => (StatusCode::INTERNAL_SERVER_ERROR, "storage error".to_string()),
            AppError::Other(_) => (StatusCode::INTERNAL_SERVER_ERROR, "internal error".to_string()),
        };
        tracing::error!(error = %self, "request failed");
        (status, Json(json!({ "error": msg }))).into_response()
    }
}
