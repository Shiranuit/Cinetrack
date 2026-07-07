//! Language-tagged aliases (alternate titles) in `catalog.entity_alias`, kept in
//! step with each series/movie on upsert. Search restricts alias matching to the
//! user's languages via this table; the flat `aliases` column still powers the
//! "also known as" display.

use serde_json::Value;

use crate::{error::AppResult, state::AppState};

/// Replace an entity's aliases with the (language, name) pairs from its raw
/// `aliases` array (`[{name, language}, …]`). Best-effort; callers ignore failures.
pub async fn store_for(state: &AppState, entity_type: &str, entity_id: i64, data: &Value) -> AppResult<()> {
    let mut langs: Vec<Option<String>> = Vec::new();
    let mut names: Vec<String> = Vec::new();
    if let Some(arr) = data["aliases"].as_array() {
        for a in arr {
            // `/extended` gives {name, language}; `/search` gives a bare string.
            let Some(name) = a["name"].as_str().or_else(|| a.as_str()).map(str::trim).filter(|s| !s.is_empty())
            else {
                continue;
            };
            names.push(name.to_string());
            langs.push(a["language"].as_str().filter(|s| !s.is_empty()).map(str::to_string));
        }
    }

    let mut tx = state.db.begin().await?;
    sqlx::query("DELETE FROM catalog.entity_alias WHERE entity_type = $1 AND entity_id = $2")
        .bind(entity_type)
        .bind(entity_id)
        .execute(&mut *tx)
        .await?;
    if !names.is_empty() {
        sqlx::query(
            "INSERT INTO catalog.entity_alias (entity_type, entity_id, language, name) \
             SELECT $1, $2, l, n FROM unnest($3::text[], $4::text[]) AS u(l, n)",
        )
        .bind(entity_type)
        .bind(entity_id)
        .bind(&langs)
        .bind(&names)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(())
}
