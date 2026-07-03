//! Unit tests for the import module's pure parsers: CSV cell coercion
//! (`source`) and the Go-`fmt` favorites blob parser (`gomap`).

use std::collections::HashMap;

use super::gomap::parse_favorite_objects;
use super::source::{Row, boolv, i32v, i64v, s, ts_utc};

fn row(pairs: &[(&str, &str)]) -> Row {
    pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect::<HashMap<_, _>>()
}

// ---- source cell coercion --------------------------------------------------

#[test]
fn s_trims_and_treats_blank_as_absent() {
    let r = row(&[("a", "  hi  "), ("blank", "   "), ("empty", "")]);
    assert_eq!(s(&r, "a"), Some("hi"));
    assert_eq!(s(&r, "blank"), None);
    assert_eq!(s(&r, "empty"), None);
    assert_eq!(s(&r, "missing"), None);
}

#[test]
fn i64v_and_i32v_parse_numbers_only() {
    let r = row(&[("n", "74796"), ("bad", "12x"), ("blank", " ")]);
    assert_eq!(i64v(&r, "n"), Some(74796));
    assert_eq!(i32v(&r, "n"), Some(74796));
    assert_eq!(i64v(&r, "bad"), None);
    assert_eq!(i32v(&r, "blank"), None);
    assert_eq!(i64v(&r, "missing"), None);
}

#[test]
fn boolv_reads_tvtime_style_flags() {
    let r = row(&[("one", "1"), ("zero", "0"), ("t", "true"), ("f", "false"), ("blank", "")]);
    assert_eq!(boolv(&r, "one"), Some(true));
    assert_eq!(boolv(&r, "zero"), Some(false));
    assert_eq!(boolv(&r, "t"), Some(true));
    assert_eq!(boolv(&r, "f"), Some(false));
    assert_eq!(boolv(&r, "blank"), None); // absent, not `false`
    assert_eq!(boolv(&r, "missing"), None);
}

#[test]
fn ts_utc_pins_naive_timestamp_to_utc() {
    let r = row(&[("t", "2024-08-05 17:42:31"), ("blank", "")]);
    assert_eq!(ts_utc(&r, "t").as_deref(), Some("2024-08-05 17:42:31+00"));
    assert_eq!(ts_utc(&r, "blank"), None);
}

// ---- gomap favorites blob --------------------------------------------------

#[test]
fn gomap_parses_favorite_objects() {
    let blob = "[map[created_at:1.660769713e+09 id:371028 type:series] \
                map[created_at:1.660769716e+09 id:74796 type:series]]";
    let items = parse_favorite_objects(blob);
    assert_eq!(items.len(), 2);
    assert_eq!(items[0].id, 371028);
    assert_eq!(items[1].id, 74796);
    assert_eq!(items[0].kind, "series");
}

#[test]
fn gomap_defaults_kind_and_skips_members_without_id() {
    // One member has no id (dropped), one has no type (defaults to "series").
    let blob = "[map[created_at:1.0e+09 type:movie] map[id:555]]";
    let items = parse_favorite_objects(blob);
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].id, 555);
    assert_eq!(items[0].kind, "series");
}

#[test]
fn gomap_handles_empty_blob() {
    assert!(parse_favorite_objects("[]").is_empty());
    assert!(parse_favorite_objects("").is_empty());
}

// ---- dead-id name matching (normalize / levenshtein / exact / fuzzy) --------

use super::{best_fuzzy_match, exact_name_match, levenshtein, normalize};
use serde_json::json;

#[test]
fn normalize_strips_punctuation_case_and_parentheticals() {
    assert_eq!(normalize("Fate/stay night: Unlimited Blade Works"), "fatestaynightunlimitedbladeworks");
    assert_eq!(normalize("Fate Stay Night Unlimited Blade Works"), "fatestaynightunlimitedbladeworks");
    assert_eq!(normalize("The Seven Deadly Sins (Nanatsu no Taizai)"), "thesevendeadlysins");
    assert_eq!(normalize("Mahou Tsukai No Yome"), "mahoutsukainoyome");
}

#[test]
fn levenshtein_basic_distances() {
    let d = |a: &str, b: &str| levenshtein(&a.chars().collect::<Vec<_>>(), &b.chars().collect::<Vec<_>>());
    assert_eq!(d("kitten", "sitting"), 3);
    assert_eq!(d("frankxx", "franxx"), 1);
    assert_eq!(d("same", "same"), 0);
    assert_eq!(d("", "abc"), 3);
}

fn result(id: &str, name: &str, translations: serde_json::Value, aliases: serde_json::Value) -> serde_json::Value {
    json!({ "tvdb_id": id, "name": name, "translations": translations, "aliases": aliases })
}

#[test]
fn exact_match_hits_name_translation_or_alias() {
    let r = result("275798", "Fate/Zero", json!({ "eng": "Fate Zero EN" }), json!(["Fate Zero", "フェイト/ゼロ"]));
    // base name (case-insensitive)
    assert_eq!(exact_name_match(&r, "fate/zero"), Some(275798));
    // via alias
    assert_eq!(exact_name_match(&r, "Fate Zero"), Some(275798));
    // via translation
    assert_eq!(exact_name_match(&r, "fate zero en"), Some(275798));
    // no exact match
    assert_eq!(exact_name_match(&r, "Fate Apocrypha"), None);
}

#[test]
fn fuzzy_match_recovers_typo_and_punctuation_variants() {
    // Typo "FrankXX" vs canonical "FRANXX" → normalized distance 1.
    let franxx = result("1", "DARLING in the FRANXX", json!({}), json!([]));
    let m = best_fuzzy_match(std::slice::from_ref(&franxx), "Darling in the FrankXX");
    assert_eq!(m.map(|(id, _, _)| id), Some(1));

    // Punctuation-only difference → normalized-exact (distance 0).
    let ubw = result("2", "Fate/stay night: Unlimited Blade Works", json!({}), json!([]));
    let m = best_fuzzy_match(std::slice::from_ref(&ubw), "Fate Stay Night Unlimited Blade Works");
    assert_eq!(m.map(|(id, _, d)| (id, d)), Some((2, 0)));
}

#[test]
fn fuzzy_match_rejects_unrelated_titles() {
    let other = result("9", "One Piece", json!({}), json!([]));
    assert!(best_fuzzy_match(std::slice::from_ref(&other), "Naruto Shippuden").is_none());
}
