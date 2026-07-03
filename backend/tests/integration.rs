//! DB integration tests: populate a throwaway Postgres, run the library's real
//! queries against it, assert, then clean up. Skipped when `TEST_DATABASE_URL`
//! is unset (see tests/common/mod.rs).

mod common;

use backend::catalog::discover::{self, Filters};
use backend::tracking;

fn langs() -> Vec<String> {
    vec!["eng".to_string()]
}

fn filters(kind: &str) -> Filters {
    Filters { kind: kind.into(), sort: "popularity".into(), limit: 100, ..Default::default() }
}

/// The library query buckets each tracked show into the right category and hides
/// `unavailable` (dead-id) shows entirely.
#[tokio::test]
async fn library_categorizes_and_hides_unavailable() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    common::insert_user(&state.db, 1, "lib@test.local").await;

    // not_started: followed, nothing seen.
    common::insert_series(&state.db, 10, "NotStarted", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 10, true, false).await;

    // watching: seen some, watched recently, no lastAired match.
    common::insert_series(&state.db, 20, "Watching", Some(2021), Some(45), Some(2.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 20, true, false).await;
    common::set_user_show(&state.db, 1, 20, "nb_episodes_seen", "5").await;
    common::watch_ago(&state.db, 1, 20, 201, "w-recent", 2).await;

    // stale: seen some, last watch 40 days ago.
    common::insert_series(&state.db, 30, "Stale", Some(2019), Some(45), Some(3.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 30, true, false).await;
    common::set_user_show(&state.db, 1, 30, "nb_episodes_seen", "5").await;
    common::watch_ago(&state.db, 1, 30, 301, "w-old", 40).await;

    // up_to_date: seen the lastAired episode.
    common::insert_series(&state.db, 40, "UpToDate", Some(2018), Some(45), Some(4.0), Some("eng"),
        serde_json::json!({ "lastAired": "2024-01-10" })).await;
    common::follow(&state.db, 1, 40, true, false).await;
    common::set_user_show(&state.db, 1, 40, "nb_episodes_seen", "8").await;
    common::insert_episode(&state.db, 401, 40, 3, 12, "2024-01-10", "Finale").await;
    common::watch_ago(&state.db, 1, 40, 401, "w-finale", 100).await; // long ago, but caught up

    // stopped: status = stopped.
    common::insert_series(&state.db, 50, "Stopped", Some(2017), Some(45), Some(5.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 50, true, false).await;
    common::set_user_show(&state.db, 1, 50, "nb_episodes_seen", "3").await;
    common::set_user_show(&state.db, 1, 50, "status", "'stopped'").await;

    // unavailable: dead id, must be hidden from every bucket.
    common::insert_series(&state.db, 60, "Dead", Some(2016), Some(45), Some(6.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 60, true, false).await;
    common::set_user_show(&state.db, 1, 60, "unavailable", "true").await;

    let lib = tracking::library(&state, 1, &langs()).await.unwrap();

    let names = |v: &[tracking::LibraryShow]| v.iter().filter_map(|s| s.name.clone()).collect::<Vec<_>>();
    assert_eq!(names(&lib.not_started), vec!["NotStarted"]);
    assert_eq!(names(&lib.watching), vec!["Watching"]);
    assert_eq!(names(&lib.stale), vec!["Stale"]);
    assert_eq!(names(&lib.up_to_date), vec!["UpToDate"]);
    assert_eq!(names(&lib.stopped), vec!["Stopped"]);

    // "Dead" appears in NO bucket.
    let all: Vec<String> = [&lib.watching, &lib.up_to_date, &lib.stale, &lib.not_started, &lib.stopped]
        .iter()
        .flat_map(|v| names(v))
        .collect();
    assert!(!all.contains(&"Dead".to_string()), "unavailable show leaked into library: {all:?}");
}

/// Advanced discover filters run over the mirrored catalog: type (anime),
/// genre ALL-include / NONE-exclude, year and runtime ranges.
#[tokio::test]
async fn discover_applies_advanced_filters() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    // Japanese anime, Action(19)+Anime(27)+Martial Arts(35), 2004, 25m.
    common::insert_series(&state.db, 74796, "Bleach", Some(2004), Some(25), Some(90.0), Some("jpn"), serde_json::json!({})).await;
    common::set_genres(&state.db, 74796, &[(19, "Action"), (27, "Anime"), (35, "Martial Arts")]).await;
    // English drama, Drama(11), 2016, 55m.
    common::insert_series(&state.db, 100, "DramaShow", Some(2016), Some(55), Some(80.0), Some("eng"), serde_json::json!({})).await;
    common::set_genres(&state.db, 100, &[(11, "Drama")]).await;
    // English action, Action(19), 1999, 45m.
    common::insert_series(&state.db, 101, "OldAction", Some(1999), Some(45), Some(70.0), Some("eng"), serde_json::json!({})).await;
    common::set_genres(&state.db, 101, &[(19, "Action")]).await;

    let ids = |v: &[backend::catalog::search::SearchResult]| v.iter().filter_map(|r| r.tvdb_id).collect::<Vec<_>>();

    // anime type → only the jpn-original series.
    let r = discover::search_db(&state, &filters("anime"), &langs()).await.unwrap();
    assert_eq!(ids(&r), vec![74796]);

    // include Action(19) → Bleach + OldAction (both have it), sorted by score desc.
    let f = Filters { genres_include: vec![19], ..filters("series") };
    assert_eq!(ids(&discover::search_db(&state, &f, &langs()).await.unwrap()), vec![74796, 101]);

    // include Action(19) AND Martial Arts(35) → only Bleach.
    let f = Filters { genres_include: vec![19, 35], ..filters("series") };
    assert_eq!(ids(&discover::search_db(&state, &f, &langs()).await.unwrap()), vec![74796]);

    // include Action(19) but exclude Anime(27) → only OldAction.
    let f = Filters { genres_include: vec![19], genres_exclude: vec![27], ..filters("series") };
    assert_eq!(ids(&discover::search_db(&state, &f, &langs()).await.unwrap()), vec![101]);

    // year range 2000..=2020 → excludes OldAction (1999).
    let f = Filters { year_min: Some(2000), year_max: Some(2020), ..filters("series") };
    let got = ids(&discover::search_db(&state, &f, &langs()).await.unwrap());
    assert!(got.contains(&74796) && got.contains(&100) && !got.contains(&101), "{got:?}");

    // runtime <= 30m → only the 25m anime.
    let f = Filters { runtime_max: Some(30), ..filters("series") };
    assert_eq!(ids(&discover::search_db(&state, &f, &langs()).await.unwrap()), vec![74796]);
}

/// The library-scoped filter returns only the user's tracked shows, honoring
/// facet filters (genre, episode count).
#[tokio::test]
async fn library_filter_scopes_to_tracked_shows() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    common::insert_user(&state.db, 1, "libfilter@test.local").await;

    // Tracked action show with 300 episodes.
    common::insert_series(&state.db, 10, "Tracked", Some(2010), Some(24), Some(9.0), Some("jpn"), serde_json::json!({})).await;
    common::set_genres(&state.db, 10, &[(19, "Action")]).await;
    common::set_episode_count(&state.db, 10, 300).await;
    common::follow(&state.db, 1, 10, true, false).await;

    // Tracked drama show with 12 episodes.
    common::insert_series(&state.db, 11, "TrackedDrama", Some(2018), Some(45), Some(8.0), Some("eng"), serde_json::json!({})).await;
    common::set_genres(&state.db, 11, &[(11, "Drama")]).await;
    common::set_episode_count(&state.db, 11, 12).await;
    common::follow(&state.db, 1, 11, true, false).await;

    // An Action show the user does NOT track — must never appear in library results.
    common::insert_series(&state.db, 20, "Untracked", Some(2011), Some(24), Some(7.0), Some("jpn"), serde_json::json!({})).await;
    common::set_genres(&state.db, 20, &[(19, "Action")]).await;

    let ids = |v: &[backend::catalog::search::SearchResult]| v.iter().filter_map(|r| r.tvdb_id).collect::<Vec<_>>();

    // No filters → both tracked shows, not the untracked one.
    let f = Filters { library_user: Some(1), ..filters("series") };
    let mut got = ids(&discover::search_db(&state, &f, &langs()).await.unwrap());
    got.sort();
    assert_eq!(got, vec![10, 11]);

    // Genre = Action → only the tracked action show (untracked Action excluded by scope).
    let f = Filters { library_user: Some(1), genres_include: vec![19], ..filters("series") };
    assert_eq!(ids(&discover::search_db(&state, &f, &langs()).await.unwrap()), vec![10]);

    // episodes >= 100 → only the 300-episode show.
    let f = Filters { library_user: Some(1), episodes_min: Some(100), ..filters("series") };
    assert_eq!(ids(&discover::search_db(&state, &f, &langs()).await.unwrap()), vec![10]);
}

/// The calendar surfaces a followed series' next-aired episode with S/E + time.
#[tokio::test]
async fn calendar_enriches_upcoming_episode() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    common::insert_user(&state.db, 1, "cal@test.local").await;
    common::insert_series(&state.db, 200, "Airing", Some(2022), Some(24), Some(50.0), Some("jpn"),
        serde_json::json!({ "airsTime": "22:30" })).await;
    common::follow(&state.db, 1, 200, true, false).await;
    // Two episodes in the 90-day window + one outside it (must be excluded).
    common::insert_episode_in_days(&state.db, 2001, 200, 4, 12, 5, "The Next One").await;
    common::insert_episode_in_days(&state.db, 2002, 200, 4, 13, 12, "The One After").await;
    common::insert_episode_in_days(&state.db, 2003, 200, 4, 14, 200, "Far Future").await;

    let cal = tracking::calendar(&state, 1, &langs()).await.unwrap();
    assert_eq!(cal.upcoming.len(), 2, "both in-window episodes, not the 200-day-out one");
    let it = &cal.upcoming[0]; // soonest first
    assert_eq!(it.series_id, 200);
    assert_eq!(it.season_number, Some(4));
    assert_eq!(it.episode_number, Some(12));
    assert_eq!(it.episode_name.as_deref(), Some("The Next One"));
    assert_eq!(it.time.as_deref(), Some("22:30"));
    assert!(it.date.is_some());
}

/// Recovering a dead/merged series id: re-point the user's tracking + watch
/// history to the live id, remapping episodes by (season, episode) number.
#[tokio::test]
async fn remap_moves_tracking_and_history_to_live_id() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    common::insert_user(&state.db, 1, "remap@test.local").await;

    // Dead id 999 the user tracks (flagged unavailable), with two watched episodes.
    common::insert_series(&state.db, 999, "Dead", None, None, None, None, serde_json::json!({})).await;
    common::follow(&state.db, 1, 999, true, true).await;
    common::set_user_show(&state.db, 1, 999, "unavailable", "true").await;
    common::watch_se(&state.db, 1, 999, 90001, 1, 1, "w1").await;
    common::watch_se(&state.db, 1, 999, 90002, 1, 2, "w2").await;

    // Live series 74796 with the matching episodes under new ids.
    common::insert_series(&state.db, 74796, "Live", Some(2004), Some(25), Some(9.0), Some("jpn"), serde_json::json!({})).await;
    common::insert_episode(&state.db, 111, 74796, 1, 1, "2004-10-05", "Ep1").await;
    common::insert_episode(&state.db, 112, 74796, 1, 2, "2004-10-12", "Ep2").await;

    backend::import::remap_user_series(&state, 1, 999, 74796).await.unwrap();

    // The dead row is gone; the user now tracks the live id (available, flags kept).
    let dead: i64 = sqlx::query_scalar("SELECT count(*) FROM app.user_show WHERE user_id=1 AND series_id=999")
        .fetch_one(&state.db).await.unwrap();
    assert_eq!(dead, 0);
    let (followed, favorited, unavailable, nb): (bool, bool, bool, i32) = sqlx::query_as(
        "SELECT is_followed, is_favorited, unavailable, nb_episodes_seen FROM app.user_show WHERE user_id=1 AND series_id=74796",
    ).fetch_one(&state.db).await.unwrap();
    assert!(followed && favorited && !unavailable);
    assert_eq!(nb, 2, "both watched episodes should count after remap");

    // Watch events now point at the live series + its episode ids (matched by S/E).
    let eps: Vec<i64> = sqlx::query_scalar(
        "SELECT episode_id FROM app.watch_event WHERE user_id=1 AND series_id=74796 ORDER BY episode_id",
    ).fetch_all(&state.db).await.unwrap();
    assert_eq!(eps, vec![111, 112]);
    let old_left: i64 = sqlx::query_scalar("SELECT count(*) FROM app.watch_event WHERE series_id=999")
        .fetch_one(&state.db).await.unwrap();
    assert_eq!(old_left, 0);
}

/// Confirming a pending match suggestion remaps the dead series to the live one;
/// rejecting leaves it hidden.
#[tokio::test]
async fn confirm_and_reject_match_suggestions() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    common::insert_user(&state.db, 1, "sug@test.local").await;

    // A dead series (hidden) the user tracks, with a watched episode.
    common::insert_series(&state.db, 999, "Dead", None, None, None, None, serde_json::json!({})).await;
    common::follow(&state.db, 1, 999, true, false).await;
    common::set_user_show(&state.db, 1, 999, "unavailable", "true").await;
    common::watch_se(&state.db, 1, 999, 90001, 1, 1, "s1").await;

    // The live candidate (already cached) with the matching episode.
    common::insert_series(&state.db, 74796, "Live", Some(2004), Some(25), Some(9.0), Some("jpn"), serde_json::json!({})).await;
    common::insert_episode(&state.db, 111, 74796, 1, 1, "2004-10-05", "Ep1").await;

    // A pending suggestion (as resolve_unavailable would have recorded).
    let sug_id: i64 = sqlx::query_scalar(
        "INSERT INTO app.import_match (user_id, dead_series_id, import_name, suggested_series_id, suggested_name, distance) \
         VALUES (1, 999, 'Dead', 74796, 'Live', 1) RETURNING id",
    ).fetch_one(&state.db).await.unwrap();

    // Confirm → remapped + marked confirmed.
    assert!(backend::import::confirm_suggestion(&state, 1, sug_id).await.unwrap());
    let status: String = sqlx::query_scalar("SELECT status FROM app.import_match WHERE id=$1")
        .bind(sug_id).fetch_one(&state.db).await.unwrap();
    assert_eq!(status, "confirmed");
    let live_present: i64 = sqlx::query_scalar("SELECT count(*) FROM app.user_show WHERE user_id=1 AND series_id=74796 AND NOT unavailable")
        .fetch_one(&state.db).await.unwrap();
    assert_eq!(live_present, 1, "dead series should now be the live one, visible");
    let ep: Option<i64> = sqlx::query_scalar("SELECT episode_id FROM app.watch_event WHERE user_id=1 AND series_id=74796")
        .fetch_one(&state.db).await.unwrap();
    assert_eq!(ep, Some(111), "watch event remapped to the live episode");

    // Confirming again is a no-op (already confirmed → not pending).
    assert!(!backend::import::confirm_suggestion(&state, 1, sug_id).await.unwrap());

    // A second dead series with a suggestion we reject.
    common::insert_series(&state.db, 888, "Dead2", None, None, None, None, serde_json::json!({})).await;
    common::follow(&state.db, 1, 888, true, false).await;
    common::set_user_show(&state.db, 1, 888, "unavailable", "true").await;
    let rej_id: i64 = sqlx::query_scalar(
        "INSERT INTO app.import_match (user_id, dead_series_id, import_name, suggested_series_id, distance) \
         VALUES (1, 888, 'Dead2', 74796, 2) RETURNING id",
    ).fetch_one(&state.db).await.unwrap();
    assert!(backend::import::reject_suggestion(&state, 1, rej_id).await.unwrap());
    let (status2, still_hidden): (String, bool) = (
        sqlx::query_scalar("SELECT status FROM app.import_match WHERE id=$1").bind(rej_id).fetch_one(&state.db).await.unwrap(),
        sqlx::query_scalar("SELECT unavailable FROM app.user_show WHERE user_id=1 AND series_id=888").fetch_one(&state.db).await.unwrap(),
    );
    assert_eq!(status2, "rejected");
    assert!(still_hidden, "rejected dead series stays hidden");
}

/// Deleting an account removes the user and cascades their tracking rows.
#[tokio::test]
async fn delete_account_removes_everything() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    common::insert_user(&state.db, 1, "del@test.local").await;
    common::insert_series(&state.db, 300, "Show", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 300, true, true).await;
    common::watch(&state.db, 1, 300, 3001, "w-del").await;

    tracking::delete_account(&state, 1).await.unwrap();

    let users: i64 = sqlx::query_scalar("SELECT count(*) FROM app.users WHERE id=1").fetch_one(&state.db).await.unwrap();
    let shows: i64 = sqlx::query_scalar("SELECT count(*) FROM app.user_show WHERE user_id=1").fetch_one(&state.db).await.unwrap();
    let events: i64 = sqlx::query_scalar("SELECT count(*) FROM app.watch_event WHERE user_id=1").fetch_one(&state.db).await.unwrap();
    assert_eq!((users, shows, events), (0, 0, 0));

    // Catalog (shared cache) is untouched by an account deletion.
    let series: i64 = sqlx::query_scalar("SELECT count(*) FROM catalog.series WHERE id=300").fetch_one(&state.db).await.unwrap();
    assert_eq!(series, 1);
}
