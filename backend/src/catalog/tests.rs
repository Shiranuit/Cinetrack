//! Unit tests for the catalog module's pure helpers (JSON coercion, image URL
//! normalization). No DB/network involved.

use serde_json::json;

use super::{as_i32, as_i64, image_url};

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
