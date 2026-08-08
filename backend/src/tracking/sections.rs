//! The user's Library layout: an ordered list of the fixed categories the Library
//! computes, each shown or hidden. See migration 0044.
//!
//! Storage is a full-list replace ([`set_library_sections`]) rather than per-row
//! CRUD: reordering touches every row's position anyway, and replacing the list in
//! one transaction means two devices saving concurrently can't interleave into an
//! order neither of them chose.

use uuid::Uuid;

use crate::{error::{AppError, AppResult}, state::AppState};

/// The fixed categories the Library computes, in the order a fresh account sees
/// them. Kept in sync with the DB CHECK constraint in migration 0044 and with
/// `kBuiltinLibrarySections` on the client.
pub const BUILTIN_SECTIONS: [&str; 7] =
    ["watching", "stale", "not_started", "for_later", "up_to_date", "stopped", "movies"];

/// One entry in a user's Library layout.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, sqlx::FromRow)]
pub struct LibrarySection {
    /// `None` for a default the user has never saved; the server assigns one on
    /// insert.
    pub id: Option<Uuid>,
    /// Which built-in category this row is, from [`BUILTIN_SECTIONS`].
    pub builtin: String,
    pub enabled: bool,
}

impl LibrarySection {
    fn builtin(key: &str) -> Self {
        Self { id: None, builtin: key.to_string(), enabled: true }
    }
}

/// The layout a user sees before they've customized anything: every built-in, in
/// order, all enabled.
pub fn default_sections() -> Vec<LibrarySection> {
    BUILTIN_SECTIONS.iter().map(|k| LibrarySection::builtin(k)).collect()
}

/// A user's Library layout, in display order. Falls back to [`default_sections`]
/// when they've never saved one.
///
/// Built-ins the user's saved layout doesn't mention are APPENDED (disabled, so a
/// category added after they customized doesn't silently rearrange their Library —
/// it shows up in the customize sheet waiting to be switched on). This is the same
/// "don't strand existing users" move migration 0043 made for the activity block,
/// done on read so no backfill is needed.
pub async fn library_sections(state: &AppState, user_id: Uuid) -> AppResult<Vec<LibrarySection>> {
    let mut rows = sqlx::query_as::<_, LibrarySection>(
        "SELECT id, builtin, enabled \
         FROM app.library_section WHERE user_id = $1 \
         ORDER BY position, id",
    )
    .bind(user_id)
    .fetch_all(&state.db)
    .await?;

    if rows.is_empty() {
        return Ok(default_sections());
    }
    for key in BUILTIN_SECTIONS {
        if !rows.iter().any(|s| s.builtin == key) {
            rows.push(LibrarySection { enabled: false, ..LibrarySection::builtin(key) });
        }
    }
    Ok(rows)
}

/// Replace a user's whole layout. Validates first so a rejected save leaves the
/// stored layout untouched, then swaps it inside one transaction.
///
/// Client-supplied `id`s are preserved when present, so ids stay stable across
/// saves (the client keys its reorder list on them); new sections get one from the
/// column default.
pub async fn set_library_sections(
    state: &AppState,
    user_id: Uuid,
    sections: &[LibrarySection],
) -> AppResult<Vec<LibrarySection>> {
    validate(sections)?;

    let mut tx = state.db.begin().await?;
    sqlx::query("DELETE FROM app.library_section WHERE user_id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await?;

    for (position, section) in sections.iter().enumerate() {
        sqlx::query(
            "INSERT INTO app.library_section (user_id, id, position, builtin, enabled) \
             VALUES ($1, COALESCE($2, gen_random_uuid()), $3, $4, $5)",
        )
        .bind(user_id)
        .bind(section.id)
        .bind(position as i32)
        .bind(section.builtin.as_str())
        .bind(section.enabled)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;

    library_sections(state, user_id).await
}

/// Reject a layout the read path couldn't render, with a message naming the
/// offending section — a 400 the client can show verbatim beats a 500 from the
/// CHECK constraint.
fn validate(sections: &[LibrarySection]) -> AppResult<()> {
    fn bad(msg: impl Into<String>) -> AppError {
        AppError::BadRequest(msg.into())
    }

    // Deliberately NOT a cap on the list length, and no cap on how many may be
    // enabled: the list is bounded by BUILTIN_SECTIONS, since each key may appear
    // at most once. A cap here would be one the READ path can breach by itself —
    // `library_sections` appends missing built-ins, and the client then sends back
    // what it was given and can never save again.
    let mut seen_builtin: Vec<&str> = Vec::new();
    let mut seen_id: Vec<Uuid> = Vec::new();

    for section in sections {
        if let Some(id) = section.id {
            if seen_id.contains(&id) {
                return Err(bad("duplicate section id"));
            }
            seen_id.push(id);
        }
        let key = section.builtin.as_str();
        if !BUILTIN_SECTIONS.contains(&key) {
            return Err(bad(format!("unknown built-in section '{key}'")));
        }
        if seen_builtin.contains(&key) {
            return Err(bad(format!("duplicate built-in section '{key}'")));
        }
        seen_builtin.push(key);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_cover_every_builtin_exactly_once() {
        let defaults = default_sections();
        assert_eq!(defaults.len(), BUILTIN_SECTIONS.len());
        for key in BUILTIN_SECTIONS {
            assert_eq!(defaults.iter().filter(|s| s.builtin == key).count(), 1, "{key}");
        }
        assert!(validate(&defaults).is_ok());
    }

    #[test]
    fn accepts_a_reordered_layout_with_some_hidden() {
        let layout = vec![
            LibrarySection { enabled: false, ..LibrarySection::builtin("stopped") },
            LibrarySection::builtin("watching"),
        ];
        assert!(validate(&layout).is_ok());
    }

    #[test]
    fn rejects_layouts_the_client_could_not_render() {
        // Unknown built-in — would be an invisible, unremovable row.
        assert!(validate(&[LibrarySection::builtin("nonsense")]).is_err());
        // The same built-in twice: it maps to one bucket of shows, so the second
        // would duplicate the first.
        assert!(validate(&[LibrarySection::builtin("watching"), LibrarySection::builtin("watching")]).is_err());
        // A section the user made under an older build no longer parses at all —
        // `builtin` is required, so such a payload is rejected before it reaches
        // the CHECK constraint.
        assert!(serde_json::from_str::<LibrarySection>(r#"{"id":null,"builtin":null,"enabled":true}"#).is_err());
    }

    #[test]
    fn a_read_write_round_trip_is_always_saveable() {
        // What a GET returns for a user who saved a partial layout: what they had,
        // plus every missing built-in appended DISABLED. Saving that back must be
        // accepted — otherwise the read path locks the user out of ever saving.
        let saved = [LibrarySection::builtin("watching")];
        let round_tripped: Vec<_> = saved
            .iter()
            .cloned()
            .chain(
                BUILTIN_SECTIONS
                    .iter()
                    .filter(|k| **k != "watching")
                    .map(|k| LibrarySection { enabled: false, ..LibrarySection::builtin(k) }),
            )
            .collect();
        assert_eq!(round_tripped.len(), BUILTIN_SECTIONS.len());
        assert!(validate(&round_tripped).is_ok(), "a user must always be able to save back what they were given");
    }

    #[test]
    fn ids_must_be_distinct() {
        let id = Uuid::now_v7();
        let layout = vec![
            LibrarySection { id: Some(id), ..LibrarySection::builtin("watching") },
            LibrarySection { id: Some(id), ..LibrarySection::builtin("stale") },
        ];
        assert!(validate(&layout).is_err());
    }
}
