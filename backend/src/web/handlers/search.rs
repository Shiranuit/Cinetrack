use axum::{
    Json,
    extract::{Query, State},
};
use serde::Deserialize;

use crate::{
    catalog::{self, search::SearchResult},
    error::{AppError, AppResult},
    state::AppState,
};

#[derive(Deserialize)]
pub struct SearchQuery {
    pub q: String,
    /// Optional filter: "series", "movie", "person", ...
    #[serde(rename = "type")]
    pub kind: Option<String>,
    /// Preferred language order, comma-separated (e.g. `eng,fra`). Default `eng`.
    pub langs: Option<String>,
}

pub async fn search(
    State(state): State<AppState>,
    Query(query): Query<SearchQuery>,
) -> AppResult<Json<Vec<SearchResult>>> {
    if query.q.trim().is_empty() {
        return Err(AppError::BadRequest("missing query parameter q".into()));
    }
    let langs: Vec<String> = query
        .langs
        .as_deref()
        .unwrap_or("eng")
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    Ok(Json(catalog::search::search(&state, query.q.trim(), query.kind.as_deref(), &langs).await?))
}
