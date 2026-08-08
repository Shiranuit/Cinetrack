//! The user's Library layout: an ordered list of sections, each either one of the
//! fixed categories the Library computes or a user-defined one with its own saved
//! filter. See migration 0044.
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

/// Ceiling on custom sections a user may keep, enabled or not.
pub const MAX_CUSTOM_SECTIONS: usize = 15;

/// Ceiling on sections shown at once, built-in and custom together. Every enabled
/// section is at least one query when the Library loads, so this — not the stored
/// count — is what bounds that fan-out.
pub const MAX_ACTIVE_SECTIONS: usize = 15;

/// Ceiling on a custom section's title, in characters.
const MAX_TITLE_CHARS: usize = 40;

/// Query params a custom section's saved filter may carry — exactly the keys
/// `AdvancedFilters.toQuery()` emits, minus the ones that aren't the filter's to
/// decide: `limit`/`offset` belong to the rail, `langs` to the viewer (their own
/// language preference, not the section author's), and `include_library` is a
/// Discover-only flag that means nothing inside your own library.
/// `q` IS included — a name-scoped rail is a legitimate saved filter.
const ALLOWED_FILTER_KEYS: [&str; 34] = [
    "q", "type", "sort", "dir", "genres", "exclude_genres", "tags", "exclude_tags", "networks",
    "studios", "statuses", "orig_langs", "orig_countries", "year_min", "year_max", "runtime_min",
    "runtime_max", "seasons_min", "seasons_max", "episodes_min", "episodes_max", "score_min",
    "favorites", "state",
    // Watch-history facets (library scope).
    "watched_days_min", "watched_days_max", "aired_days_min", "aired_days_max", "remaining_min",
    "remaining_max", "progress_min", "progress_max", "caught_up", "has_upcoming",
];

/// Ceiling on one filter value (the longest legitimate one is a comma-joined id
/// list, e.g. every genre at once).
const MAX_FILTER_VALUE_CHARS: usize = 300;

/// Kinds a custom section may span. Stored as a comma list in the `type` filter —
/// a section can cover several at once, which the client resolves into one query
/// per kind (`search_db` takes a single kind).
const SECTION_KINDS: [&str; 3] = ["series", "anime", "movie"];

/// One entry in a user's Library layout. Exactly one of `builtin` / (`title` +
/// `filters`) is set — see the `library_section_shape` constraint.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, sqlx::FromRow)]
pub struct LibrarySection {
    /// `None` for a default the user has never saved, and for a section the client
    /// has just created; the server assigns one on insert.
    pub id: Option<Uuid>,
    /// Built-in category key, or `None` for a user-defined section.
    pub builtin: Option<String>,
    /// Custom sections only: the user's label.
    pub title: Option<String>,
    /// Custom sections only: the saved filter as a flat query-param map.
    pub filters: Option<serde_json::Value>,
    pub enabled: bool,
}

impl LibrarySection {
    fn builtin(key: &str) -> Self {
        Self { id: None, builtin: Some(key.to_string()), title: None, filters: None, enabled: true }
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
        "SELECT id, builtin, title, filters, enabled \
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
        if !rows.iter().any(|s| s.builtin.as_deref() == Some(key)) {
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
            "INSERT INTO app.library_section (user_id, id, position, builtin, title, filters, enabled) \
             VALUES ($1, COALESCE($2, gen_random_uuid()), $3, $4, $5, $6, $7)",
        )
        .bind(user_id)
        .bind(section.id)
        .bind(position as i32)
        .bind(section.builtin.as_deref())
        .bind(section.title.as_deref().map(str::trim))
        .bind(section.filters.as_ref())
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

    // Deliberately NOT a cap on the list length: `library_sections` appends missing
    // built-ins on read, so a combined cap is one the READ path can breach by
    // itself — the client then sends back what it was given and can never save
    // again. Both counts below are unaffected by that append, because appended
    // built-ins arrive disabled.
    let custom = sections.iter().filter(|s| s.builtin.is_none()).count();
    if custom > MAX_CUSTOM_SECTIONS {
        return Err(bad(format!("too many custom categories (max {MAX_CUSTOM_SECTIONS})")));
    }
    let active = sections.iter().filter(|s| s.enabled).count();
    if active > MAX_ACTIVE_SECTIONS {
        return Err(bad(format!("too many categories shown at once (max {MAX_ACTIVE_SECTIONS})")));
    }
    let mut seen_builtin: Vec<&str> = Vec::new();
    let mut seen_id: Vec<Uuid> = Vec::new();

    for section in sections {
        if let Some(id) = section.id {
            if seen_id.contains(&id) {
                return Err(bad("duplicate section id"));
            }
            seen_id.push(id);
        }
        match (&section.builtin, &section.title, &section.filters) {
            // Built-in: known key, no custom payload, at most once.
            (Some(key), None, None) => {
                if !BUILTIN_SECTIONS.contains(&key.as_str()) {
                    return Err(bad(format!("unknown built-in section '{key}'")));
                }
                if seen_builtin.contains(&key.as_str()) {
                    return Err(bad(format!("duplicate built-in section '{key}'")));
                }
                seen_builtin.push(key);
            }
            // Custom: a usable title and a filter we know how to replay.
            (None, Some(title), Some(filters)) => {
                let title = title.trim();
                if title.is_empty() {
                    return Err(bad("a custom section needs a title"));
                }
                if title.chars().count() > MAX_TITLE_CHARS {
                    return Err(bad(format!("section title too long (max {MAX_TITLE_CHARS} characters)")));
                }
                validate_filters(filters)?;
            }
            _ => {
                return Err(bad("a section must be either a built-in or a titled custom filter"));
            }
        }
    }
    Ok(())
}

/// A saved filter must be a flat string map drawn from [`ALLOWED_FILTER_KEYS`] —
/// it's replayed verbatim as query params, so anything else is either junk we'd
/// store forever or a key the filter endpoint would ignore anyway.
fn validate_filters(filters: &serde_json::Value) -> AppResult<()> {
    let Some(map) = filters.as_object() else {
        return Err(AppError::BadRequest("section filters must be an object".into()));
    };
    for (key, value) in map {
        if !ALLOWED_FILTER_KEYS.contains(&key.as_str()) {
            return Err(AppError::BadRequest(format!("unsupported filter '{key}'")));
        }
        let Some(text) = value.as_str() else {
            return Err(AppError::BadRequest(format!("filter '{key}' must be a string")));
        };
        if text.chars().count() > MAX_FILTER_VALUE_CHARS {
            return Err(AppError::BadRequest(format!("filter '{key}' is too long")));
        }
        // `type` is the one filter the client doesn't replay verbatim: a section can
        // span several kinds, and since `search_db` takes exactly one, the client
        // fans out one request per kind and merges. Validate the parts so a typo
        // can't silently produce a rail that queries nothing.
        if key == "type" {
            for kind in text.split(',').map(str::trim).filter(|k| !k.is_empty()) {
                if !SECTION_KINDS.contains(&kind) {
                    return Err(AppError::BadRequest(format!("unknown section type '{kind}'")));
                }
            }
        }
        // Likewise `state`: a bucket the classification never emits would be a rail
        // that always renders empty, with nothing to explain why.
        if key == "state" {
            for st in text.split(',').map(str::trim).filter(|v| !v.is_empty()) {
                if !crate::tracking::state::is_valid(st) {
                    return Err(AppError::BadRequest(format!("unknown library state '{st}'")));
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn custom(title: &str, filters: serde_json::Value) -> LibrarySection {
        LibrarySection { id: None, builtin: None, title: Some(title.into()), filters: Some(filters), enabled: true }
    }

    #[test]
    fn defaults_cover_every_builtin_exactly_once() {
        let defaults = default_sections();
        assert_eq!(defaults.len(), BUILTIN_SECTIONS.len());
        for key in BUILTIN_SECTIONS {
            assert_eq!(defaults.iter().filter(|s| s.builtin.as_deref() == Some(key)).count(), 1, "{key}");
        }
        assert!(validate(&defaults).is_ok());
    }

    #[test]
    fn accepts_a_mixed_layout_of_builtins_and_custom_sections() {
        let layout = vec![
            LibrarySection::builtin("watching"),
            custom("90s sci-fi", json!({"type": "series", "genres": "12", "year_max": "1999"})),
            LibrarySection { enabled: false, ..LibrarySection::builtin("stopped") },
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
        // Neither shape.
        assert!(validate(&[LibrarySection { id: None, builtin: None, title: None, filters: None, enabled: true }]).is_err());
        // Custom with no usable title.
        assert!(validate(&[custom("   ", json!({}))]).is_err());
        assert!(validate(&[custom(&"x".repeat(MAX_TITLE_CHARS + 1), json!({}))]).is_err());
    }

    #[test]
    fn rejects_filters_the_library_endpoint_would_not_understand() {
        // Not a param the filter endpoint takes.
        assert!(validate(&[custom("bad", json!({"drop_table": "1"}))]).is_err());
        // Paging is the rail's business, not the saved filter's.
        assert!(validate(&[custom("bad", json!({"limit": "500"}))]).is_err());
        // Values are replayed as query params, so they must be strings.
        assert!(validate(&[custom("bad", json!({"year_min": 1999}))]).is_err());
        assert!(validate(&[custom("bad", json!({"q": "x".repeat(MAX_FILTER_VALUE_CHARS + 1)}))]).is_err());
        // An empty filter is fine: "everything in my library, sorted this way".
        assert!(validate(&[custom("all", json!({}))]).is_ok());
    }

    #[test]
    fn the_two_caps_are_independent_and_survive_a_read_write_round_trip() {
        // The lockout this replaces: a cap on the LIST length is one the read path
        // breaches by itself, because `library_sections` appends missing built-ins.
        // Appended built-ins are disabled, so neither count moves — which is exactly
        // why the caps are phrased this way.
        let customs: Vec<_> = (0..MAX_CUSTOM_SECTIONS)
            .map(|i| custom(&format!("c{i}"), json!({})))
            .collect();
        assert!(validate(&customs).is_ok(), "{MAX_CUSTOM_SECTIONS} custom sections is the limit, not over it");

        let mut too_many = customs.clone();
        too_many.push(custom("one too many", json!({})));
        assert!(validate(&too_many).is_err());

        // What a GET returns for that user: the customs plus every built-in,
        // appended DISABLED. Saving it back must be accepted.
        let round_tripped: Vec<_> = customs
            .iter()
            .cloned()
            .chain(BUILTIN_SECTIONS.iter().map(|k| LibrarySection { enabled: false, ..LibrarySection::builtin(k) }))
            .collect();
        assert!(round_tripped.len() > MAX_ACTIVE_SECTIONS, "the round trip really does exceed the old combined cap");
        assert!(validate(&round_tripped).is_ok(), "a user must always be able to save back what they were given");
    }

    #[test]
    fn the_active_cap_counts_builtins_and_custom_together() {
        // 15 shown at once, whatever the mix.
        let mut layout: Vec<_> = BUILTIN_SECTIONS.iter().map(|k| LibrarySection::builtin(k)).collect();
        layout.extend((0..8).map(|i| custom(&format!("c{i}"), json!({}))));
        assert_eq!(layout.iter().filter(|s| s.enabled).count(), 15);
        assert!(validate(&layout).is_ok());

        layout.push(custom("sixteenth", json!({})));
        assert!(validate(&layout).is_err(), "a 16th enabled section is rejected");

        // ...but the same layout is fine once it's hidden, since hidden sections
        // cost nothing at load time.
        let last = layout.len() - 1;
        layout[last] = LibrarySection { enabled: false, ..layout[last].clone() };
        assert!(validate(&layout).is_ok());
    }

    #[test]
    fn the_default_layout_and_a_reset_layout_are_both_within_the_caps() {
        // `default_sections` and the client's "reset layout" both enable every
        // built-in; that must stay legal by construction.
        assert!(BUILTIN_SECTIONS.len() <= MAX_ACTIVE_SECTIONS);
        assert!(validate(&default_sections()).is_ok());
    }

    #[test]
    fn a_section_may_filter_on_library_buckets() {
        // The whole point of the duplicate action: a saved section can pin the same
        // buckets the Library rails use.
        assert!(validate(&[custom("watching", json!({"type": "series", "state": "watching"}))]).is_ok());
        assert!(validate(&[custom("busy", json!({"state": "watching,stale"}))]).is_ok());
        assert!(validate(&[custom("bad", json!({"state": "in_progress"}))]).is_err());
    }

    #[test]
    fn a_section_may_span_several_kinds() {
        // One kind, or several — the client fans out one query per kind.
        for kinds in ["series", "movie", "series,movie", "anime,movie", "series,anime,movie"] {
            assert!(validate(&[custom("mixed", json!({"type": kinds}))]).is_ok(), "{kinds}");
        }
        // A typo would silently produce a rail that queries nothing.
        assert!(validate(&[custom("bad", json!({"type": "serie"}))]).is_err());
        assert!(validate(&[custom("bad", json!({"type": "series,books"}))]).is_err());
    }
}
