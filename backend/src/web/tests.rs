//! Unit tests for the web layer's pure query-string helpers.

use super::query::{LangQuery, LangsQuery, csv_ids};

// ---- LangQuery::resolve (single language, with the "original" sentinel) -----

#[test]
fn lang_query_defaults_to_english() {
    assert_eq!(LangQuery { lang: None }.resolve().as_deref(), Some("eng"));
}

#[test]
fn lang_query_original_and_empty_mean_untranslated() {
    assert_eq!(LangQuery { lang: Some("original".into()) }.resolve(), None);
    assert_eq!(LangQuery { lang: Some(String::new()) }.resolve(), None);
}

#[test]
fn lang_query_passes_through_an_explicit_code() {
    assert_eq!(LangQuery { lang: Some("jpn".into()) }.resolve().as_deref(), Some("jpn"));
}

// ---- LangsQuery::list (ordered priority list) ------------------------------

#[test]
fn langs_query_defaults_to_english_list() {
    assert_eq!(LangsQuery { langs: None }.list(), vec!["eng".to_string()]);
}

#[test]
fn langs_query_splits_trims_and_preserves_order() {
    assert_eq!(
        LangsQuery { langs: Some(" fra , eng ,jpn".into()) }.list(),
        vec!["fra".to_string(), "eng".to_string(), "jpn".to_string()],
    );
}

#[test]
fn langs_query_blank_falls_back_to_english() {
    assert_eq!(LangsQuery { langs: Some("  ,  ".into()) }.list(), vec!["eng".to_string()]);
}

// ---- csv_ids ---------------------------------------------------------------

#[test]
fn csv_ids_parses_and_drops_junk() {
    assert_eq!(csv_ids(Some("1, 2 ,x,,3")), vec![1, 2, 3]);
    assert_eq!(csv_ids(Some("19,35")), vec![19, 35]);
}

#[test]
fn csv_ids_empty_and_none_are_empty() {
    assert!(csv_ids(None).is_empty());
    assert!(csv_ids(Some("")).is_empty());
    assert!(csv_ids(Some("nope")).is_empty());
}
