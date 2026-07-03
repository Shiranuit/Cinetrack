//! Unit tests for the catalog module's pure helpers (JSON coercion, image URL
//! normalization, TheTVDB search-result mapping). No DB/network involved.

use serde_json::json;

use super::search::map_result;
use super::{as_i32, as_i64, image_url};

fn langs(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| s.to_string()).collect()
}

// ---- as_i32 / as_i64 (TheTVDB sends numbers OR numeric strings) -------------

#[test]
fn as_i32_accepts_number_and_numeric_string() {
    assert_eq!(as_i32(&json!(2004)), Some(2004));
    assert_eq!(as_i32(&json!("2004")), Some(2004));
}

#[test]
fn as_i32_rejects_non_numeric_and_missing() {
    assert_eq!(as_i32(&json!("nope")), None);
    assert_eq!(as_i32(&json!(null)), None);
    assert_eq!(as_i32(&json!({})), None);
}

#[test]
fn as_i64_accepts_number_and_numeric_string() {
    assert_eq!(as_i64(&json!(74796)), Some(74796));
    assert_eq!(as_i64(&json!("74796")), Some(74796));
    assert_eq!(as_i64(&json!("x")), None);
}

// ---- image_url (relative /banners paths → absolute CDN URL) -----------------

#[test]
fn image_url_prefixes_relative_paths() {
    assert_eq!(
        image_url(&json!("/banners/episodes/1.jpg")).as_deref(),
        Some("https://artworks.thetvdb.com/banners/episodes/1.jpg"),
    );
}

#[test]
fn image_url_leaves_absolute_urls_untouched() {
    assert_eq!(
        image_url(&json!("https://artworks.thetvdb.com/x.jpg")).as_deref(),
        Some("https://artworks.thetvdb.com/x.jpg"),
    );
}

#[test]
fn image_url_treats_empty_and_non_string_as_none() {
    assert_eq!(image_url(&json!("")), None);
    assert_eq!(image_url(&json!(null)), None);
    assert_eq!(image_url(&json!(123)), None);
}

// ---- map_result (search JSON → SearchResult, with language preference) ------

#[test]
fn map_result_prefers_first_available_translation() {
    let r = json!({
        "tvdb_id": "74796",
        "type": "series",
        "name": "Bleach",
        "year": "2004",
        "image_url": "https://x/p.jpg",
        "translations": { "fra": "Bleach VF", "eng": "Bleach EN" },
        "overviews": { "fra": "résumé", "eng": "summary" },
    });
    let out = map_result(&r, &langs(&["fra", "eng"]));
    assert_eq!(out.tvdb_id, Some(74796));
    assert_eq!(out.kind.as_deref(), Some("series"));
    assert_eq!(out.name.as_deref(), Some("Bleach VF"));
    assert_eq!(out.overview.as_deref(), Some("résumé"));
    assert_eq!(out.year, Some(2004));
}

#[test]
fn map_result_falls_back_to_base_name_when_no_translation() {
    let r = json!({
        "tvdb_id": "1",
        "type": "movie",
        "name": "Base Name",
        "translations": { "spa": "Nombre" },
    });
    // Preferred langs absent from the translations map → base name.
    let out = map_result(&r, &langs(&["eng", "fra"]));
    assert_eq!(out.name.as_deref(), Some("Base Name"));
    assert_eq!(out.kind.as_deref(), Some("movie"));
}

#[test]
fn map_result_handles_missing_fields() {
    let out = map_result(&json!({}), &langs(&["eng"]));
    assert_eq!(out.tvdb_id, None);
    assert_eq!(out.name, None);
    assert_eq!(out.year, None);
}
