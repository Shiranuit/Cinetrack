use axum::{
    Json,
    extract::{Path, Query, State},
};

use crate::{
    catalog::{self, models::EpisodeRow},
    error::AppResult,
    state::AppState,
    web::query::LangQuery,
};

pub async fn get_episode(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    Query(q): Query<LangQuery>,
) -> AppResult<Json<EpisodeRow>> {
    Ok(Json(catalog::episode::get(&state, id, q.resolve().as_deref()).await?))
}
