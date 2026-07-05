use uuid::Uuid;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::{
    Json,
    extract::{Multipart, Path, State},
    http::header,
    response::{IntoResponse, Response},
};
use serde_json::{Value, json};

use crate::{auth::AuthUser, error::{AppError, AppResult}, import, state::AppState};

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
}

/// Max size for an uploaded avatar / cover (defence-in-depth on top of the global
/// request body limit).
const MAX_IMAGE_BYTES: usize = 5 * 1024 * 1024;

/// Read the first file field's bytes (+ content type) from a multipart body.
async fn first_file(mut mp: Multipart) -> AppResult<(Vec<u8>, String)> {
    while let Some(field) = mp.next_field().await.map_err(|e| AppError::BadRequest(format!("multipart: {e}")))? {
        let ct = field.content_type().unwrap_or("application/octet-stream").to_string();
        let bytes = field.bytes().await.map_err(|e| AppError::BadRequest(format!("read upload: {e}")))?;
        return Ok((bytes.to_vec(), ct));
    }
    Err(AppError::BadRequest("no file in upload".into()))
}

/// Determine the real image type from magic bytes — never trust the client's
/// Content-Type. Returns the canonical MIME for the allowed formats, else `None`.
/// This is what stops a user uploading HTML/SVG-with-script as their "avatar" and
/// having us serve it back as active content from our own domain.
fn sniff_image(bytes: &[u8]) -> Option<&'static str> {
    if bytes.len() < 12 {
        return None;
    }
    if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        Some("image/png")
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("image/jpeg")
    } else if bytes.starts_with(b"GIF87a") || bytes.starts_with(b"GIF89a") {
        Some("image/gif")
    } else if &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some("image/webp")
    } else {
        None
    }
}

async fn upload_image(state: &AppState, user_id: Uuid, kind: &str, mp: Multipart) -> AppResult<String> {
    let storage = state.storage.as_ref().ok_or_else(|| AppError::Storage("object storage not configured".into()))?;
    let (bytes, _client_ct) = first_file(mp).await?;
    if bytes.len() > MAX_IMAGE_BYTES {
        return Err(AppError::BadRequest("image too large (max 5 MB)".into()));
    }
    let ct = sniff_image(&bytes)
        .ok_or_else(|| AppError::BadRequest("unsupported image type (PNG, JPEG, GIF or WebP only)".into()))?;
    let key = format!("users/{user_id}/{kind}");
    storage.put(&key, &bytes, ct).await?;
    let url = format!("{}/api/users/{user_id}/{kind}?v={}", state.config.public_base_url, now());
    let col = if kind == "avatar" { "avatar_url" } else { "cover_url" };
    sqlx::query(&format!("UPDATE app.users SET {col} = $1, updated_at = now() WHERE id = $2"))
        .bind(&url)
        .bind(user_id)
        .execute(&state.db)
        .await?;
    Ok(url)
}

pub async fn upload_avatar(AuthUser(uid): AuthUser, State(state): State<AppState>, mp: Multipart) -> AppResult<Json<Value>> {
    let url = upload_image(&state, uid, "avatar", mp).await?;
    Ok(Json(json!({ "avatar_url": url })))
}

pub async fn upload_cover(AuthUser(uid): AuthUser, State(state): State<AppState>, mp: Multipart) -> AppResult<Json<Value>> {
    let url = upload_image(&state, uid, "cover", mp).await?;
    Ok(Json(json!({ "cover_url": url })))
}

async fn serve(state: &AppState, user_id: Uuid, kind: &str) -> AppResult<Response> {
    let storage = state.storage.as_ref().ok_or(AppError::NotFound)?;
    let (bytes, ct) = storage.get_with_type(&format!("users/{user_id}/{kind}")).await?;
    Ok((
        [
            (header::CONTENT_TYPE, ct),
            (header::CACHE_CONTROL, "public, max-age=3600".to_string()),
            // Belt-and-suspenders: never let a browser MIME-sniff stored bytes into
            // active content, even though we already validated the type on upload.
            (header::X_CONTENT_TYPE_OPTIONS, "nosniff".to_string()),
        ],
        bytes,
    )
        .into_response())
}

/// Public: serve a user's avatar / cover image from storage.
pub async fn serve_avatar(State(state): State<AppState>, Path(id): Path<Uuid>) -> AppResult<Response> {
    serve(&state, id, "avatar").await
}
pub async fn serve_cover(State(state): State<AppState>, Path(id): Path<Uuid>) -> AppResult<Response> {
    serve(&state, id, "cover").await
}

/// Import an uploaded TV Time GDPR export into the logged-in account.
pub async fn import_upload(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    mp: Multipart,
) -> AppResult<Json<import::ImportSummary>> {
    let (bytes, _) = first_file(mp).await?;
    let summary = import::run_into(&state, bytes, uid).await.map_err(AppError::Other)?;
    // Populate the catalog in the background so the library shows names/posters
    // without the user opening each show. Returns immediately.
    let bg = state.clone();
    tokio::spawn(async move { import::prefetch_user_series(&bg, uid).await });
    Ok(Json(summary))
}

/// Pending fuzzy match suggestions for the user to confirm/reject.
pub async fn import_suggestions(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    axum::extract::Query(q): axum::extract::Query<crate::web::query::LangsQuery>,
) -> AppResult<Json<Vec<import::MatchSuggestion>>> {
    Ok(Json(import::list_suggestions(&state, uid, &q.list()).await?))
}

/// A suggestion is a dead-series recovery by default, or a movie import when
/// `?type=movie`; the id spaces are per-table, so the type picks the right one.
#[derive(serde::Deserialize)]
pub struct SuggestionKind {
    #[serde(default)]
    pub r#type: String,
}

pub async fn confirm_suggestion(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
    axum::extract::Query(k): axum::extract::Query<SuggestionKind>,
) -> AppResult<Json<Value>> {
    let ok = if k.r#type == "movie" {
        import::confirm_movie_suggestion(&state, uid, id).await?
    } else {
        import::confirm_suggestion(&state, uid, id).await?
    };
    if !ok {
        return Err(AppError::NotFound);
    }
    Ok(Json(json!({ "confirmed": true })))
}

pub async fn reject_suggestion(
    AuthUser(uid): AuthUser,
    State(state): State<AppState>,
    Path(id): Path<i64>,
    axum::extract::Query(k): axum::extract::Query<SuggestionKind>,
) -> AppResult<Json<Value>> {
    let ok = if k.r#type == "movie" {
        import::reject_movie_suggestion(&state, uid, id).await?
    } else {
        import::reject_suggestion(&state, uid, id).await?
    };
    if !ok {
        return Err(AppError::NotFound);
    }
    Ok(Json(json!({ "rejected": true })))
}
