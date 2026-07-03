use axum::{
    Json,
    extract::{Path, State},
};

use crate::{
    catalog::{self, models::ArtworkRow},
    error::AppResult,
    state::AppState,
};

/// Artwork metadata. Image URLs point at TheTVDB's CDN and are loaded directly by
/// the client — we don't proxy image bytes through our own storage.
pub async fn get_artwork(
    State(state): State<AppState>,
    Path(id): Path<i64>,
) -> AppResult<Json<ArtworkRow>> {
    Ok(Json(catalog::artwork::get(&state, id).await?))
}
