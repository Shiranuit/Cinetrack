use axum::{
    Json,
    extract::{Path, Query, State},
};

use crate::{
    catalog::{self, models::SeasonRow},
    error::AppResult,
    state::AppState,
    web::query::LangQuery,
};

pub async fn get_season(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    Query(q): Query<LangQuery>,
) -> AppResult<Json<SeasonRow>> {
    Ok(Json(catalog::season::get(&state, id, q.resolve().as_deref()).await?))
}
