use super::{Frequency, SearchBaseline, SearchMode, words};

fn frequency(kind: &str, language: &str, term: &str, matches: i64, titles: i64) -> Frequency {
    Frequency {
        kind: kind.into(),
        language: language.into(),
        term: term.into(),
        matches,
        titles,
    }
}

#[test]
fn only_large_and_unselective_terms_are_limited() {
    let baseline = SearchBaseline::from_frequencies(vec![
        frequency("series", "eng", "the", 20_000, 100_000),
        frequency("series", "eng", "love", 4_999, 100_000),
        frequency("series", "eng", "rare", 5_000, 500_000),
    ]);
    let langs = vec!["eng".into()];
    assert_eq!(
        baseline.mode(Some("THE!"), "series", &langs),
        SearchMode::Exact
    );
    assert_eq!(
        baseline.mode(Some("love"), "series", &langs),
        SearchMode::Full
    );
    assert_eq!(
        baseline.mode(Some("rare"), "series", &langs),
        SearchMode::Full
    );
    assert_eq!(
        baseline.mode(Some("the office"), "series", &langs),
        SearchMode::Full
    );
    assert_eq!(
        baseline.mode(Some("the-office"), "series", &langs),
        SearchMode::Full
    );
}

#[test]
fn baseline_respects_language_kind_and_always_searchable_titles() {
    let baseline = SearchBaseline::from_frequencies(vec![
        frequency("series", "fra", "les", 10_000, 100_000),
        frequency("movie", "*", "the", 20_000, 300_000),
    ]);
    assert_eq!(
        baseline.mode(Some("les"), "series", &["eng".into()]),
        SearchMode::Full
    );
    assert_eq!(
        baseline.mode(Some("les"), "anime", &["fra".into()]),
        SearchMode::Exact
    );
    assert_eq!(
        baseline.mode(Some("the"), "movie", &["fra".into()]),
        SearchMode::Exact
    );
    assert_eq!(
        baseline.mode(Some("the"), "series", &["fra".into()]),
        SearchMode::Full
    );
}

#[test]
fn short_or_punctuation_queries_use_equality_while_absent_query_browses() {
    let baseline = SearchBaseline::default();
    assert_eq!(baseline.mode(None, "series", &[]), SearchMode::Full);
    for query in ["It", "Up", "a", "%%", " _ "] {
        assert_eq!(baseline.mode(Some(query), "movie", &[]), SearchMode::Exact);
    }
}

#[test]
fn words_keep_accents_and_non_latin_text_and_normalize_separators() {
    assert_eq!(words("  ÉCOLE—Laid-Off  "), vec!["école", "laid", "off"]);
    assert_eq!(words("進撃の巨人"), vec!["進撃の巨人"]);
}
