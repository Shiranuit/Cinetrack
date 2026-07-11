//! Unit tests for the import module's pure parsers: CSV cell coercion
//! (`source`) and the Go-`fmt` favorites blob parser (`gomap`).

use std::collections::HashMap;

use super::basename;
use super::gomap::parse_favorite_objects;
use super::source::{Row, boolv, episode_id_of, i32v, i64v, s, ts_utc};

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
fn episode_id_reads_both_export_formats() {
    // Newer export (theo, 2026-07): `tracking-prod-records-v2.csv` carries ONLY the
    // short `ep_id`. Reading `episode_id` alone here dropped the whole watch history.
    let new_fmt = row(&[("user_id", "57"), ("s_id", "355774"), ("ep_id", "6915147"), ("s_no", "1"), ("ep_no", "1")]);
    assert_eq!(episode_id_of(&new_fmt), Some(6915147));

    // Older export (shiranuit): the long `episode_id` (often alongside `ep_id`).
    let old_fmt = row(&[("s_id", "355774"), ("ep_id", "6915147"), ("episode_id", "6915147"), ("ep_no", "1")]);
    assert_eq!(episode_id_of(&old_fmt), Some(6915147));

    // A follow / stats-summary row has no episode id at all → callers skip it.
    let follow = row(&[("s_id", "355774"), ("key", "user-355774-follow"), ("is_followed", "1")]);
    assert_eq!(episode_id_of(&follow), None);

    // Blank/zero-string ids are treated as absent, not parsed to 0.
    let blank = row(&[("episode_id", ""), ("ep_id", "  ")]);
    assert_eq!(episode_id_of(&blank), None);
}

#[test]
fn basename_extracts_the_zip_filename_for_the_import_batch() {
    assert_eq!(basename("/home/u/gdpr-theo.zip").as_deref(), Some("gdpr-theo.zip"));
    assert_eq!(basename("gdpr-theo.zip").as_deref(), Some("gdpr-theo.zip"));
    assert_eq!(basename(r"C:\exports\gdpr.zip").as_deref(), Some("gdpr.zip"));
    assert_eq!(basename("/trailing/slash/"), None); // no filename to record
    assert_eq!(basename(""), None);
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

// ---- movie accumulation (v1 tracking export) -------------------------------

use super::{build_movies, movie_search_name, result_year};

#[test]
fn build_movies_groups_watched_rows_by_uuid() {
    let follow = row(&[
        ("entity_type", "movie"), ("type", "follow"), ("uuid", "u1"),
        ("movie_name", "劇場版 BLEACH 地獄篇"), ("alpha_range_key", "follow-alpha-bleach-hell-verse"),
        ("release_date", "2010-12-04 00:00:00"), ("runtime", "5400"), ("created_at", "2020-09-01 10:00:00"),
    ]);
    let watch1 = row(&[
        ("entity_type", "movie"), ("type", "watch"), ("uuid", "u1"),
        ("movie_name", "劇場版 BLEACH 地獄篇"), ("created_at", "2020-09-02 18:43:32"),
    ]);
    let rewatch = row(&[
        ("entity_type", "movie"), ("type", "rewatch_count"), ("uuid", "u1"), ("rewatch_count", "2"),
    ]);
    // An episode row (different entity_type) must be ignored.
    let ep = row(&[("entity_type", "episode"), ("type", "watch"), ("uuid", "e1")]);

    let m = build_movies(&[follow, watch1, rewatch, ep]);
    assert_eq!(m.len(), 1);
    let a = &m["u1"];
    assert!(a.watched);
    assert_eq!(a.watched_count, 3); // 1 watch + 2 rewatches
    assert_eq!(a.year, Some(2010));
    assert_eq!(a.runtime_secs, Some(5400));
    assert_eq!(a.search_name.as_deref(), Some("bleach hell verse"));
    assert_eq!(a.last_watched.as_deref(), Some("2020-09-02 18:43:32+00"));
    assert_eq!(a.followed_at.as_deref(), Some("2020-09-01 10:00:00+00"));
}

#[test]
fn build_movies_skips_zero_date_year_and_unwatched_stays_flagged() {
    // Plan-to-watch only (no `watch` row) with the zero-date sentinel year.
    let towatch = row(&[
        ("entity_type", "movie"), ("type", "towatch"), ("uuid", "u2"),
        ("movie_name", "PSYCHO-PASS PROVIDENCE"), ("release_date", "0001-01-01 00:00:00"),
    ]);
    let m = build_movies(&[towatch]);
    let a = &m["u2"];
    assert!(!a.watched);
    assert_eq!(a.year, None); // 0001 sentinel ignored
}

#[test]
fn movie_search_name_reads_the_alpha_slug() {
    let r = row(&[("alpha_range_key", "towatch-alpha-demon-slayer-infinity-train")]);
    assert_eq!(movie_search_name(&r).as_deref(), Some("demon slayer infinity train"));
    // No alpha key → nothing to search with here (falls back to the title upstream).
    assert_eq!(movie_search_name(&row(&[("alpha_range_key", "")])), None);
    assert_eq!(movie_search_name(&row(&[("x", "y")])), None);
}

#[test]
fn result_year_parses_string_or_number() {
    assert_eq!(result_year(&json!({ "year": "2021" })), Some(2021));
    assert_eq!(result_year(&json!({ "year": 2019 })), Some(2019));
    assert_eq!(result_year(&json!({ "name": "no year" })), None);
}
