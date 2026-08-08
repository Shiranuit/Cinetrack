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
    Filters { kind: kind.into(), sort: "popularity".into(), sort_desc: true, limit: 100, ..Default::default() }
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

    let lib = tracking::library(&state, common::uid(1), &langs(), "popularity", true).await.unwrap();

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

    let ids = |v: &[backend::catalog::SearchResult]| v.iter().filter_map(|r| r.tvdb_id).collect::<Vec<_>>();

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

    let ids = |v: &[backend::catalog::SearchResult]| v.iter().filter_map(|r| r.tvdb_id).collect::<Vec<_>>();

    // No filters → both tracked shows, not the untracked one.
    let f = Filters { library_user: Some(common::uid(1)), ..filters("series") };
    let mut got = ids(&discover::search_db(&state, &f, &langs()).await.unwrap());
    got.sort();
    assert_eq!(got, vec![10, 11]);

    // Genre = Action → only the tracked action show (untracked Action excluded by scope).
    let f = Filters { library_user: Some(common::uid(1)), genres_include: vec![19], ..filters("series") };
    assert_eq!(ids(&discover::search_db(&state, &f, &langs()).await.unwrap()), vec![10]);

    // episodes >= 100 → only the 300-episode show.
    let f = Filters { library_user: Some(common::uid(1)), episodes_min: Some(100), ..filters("series") };
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

    let cal = tracking::calendar(&state, common::uid(1), &langs(), None).await.unwrap();
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

    backend::import::remap_user_series(&state, common::uid(1), 999, 74796).await.unwrap();

    // The dead row is gone; the user now tracks the live id (available, flags kept).
    let dead: i64 = sqlx::query_scalar("SELECT count(*) FROM app.user_show WHERE user_id='00000000-0000-0000-0000-000000000001' AND series_id=999")
        .fetch_one(&state.db).await.unwrap();
    assert_eq!(dead, 0);
    let (followed, favorited, unavailable, nb): (bool, bool, bool, i32) = sqlx::query_as(
        "SELECT is_followed, is_favorited, unavailable, nb_episodes_seen FROM app.user_show WHERE user_id='00000000-0000-0000-0000-000000000001' AND series_id=74796",
    ).fetch_one(&state.db).await.unwrap();
    assert!(followed && favorited && !unavailable);
    assert_eq!(nb, 2, "both watched episodes should count after remap");

    // Watch events now point at the live series + its episode ids (matched by S/E).
    let eps: Vec<i64> = sqlx::query_scalar(
        "SELECT episode_id FROM app.watch_event WHERE user_id='00000000-0000-0000-0000-000000000001' AND series_id=74796 ORDER BY episode_id",
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
         VALUES ('00000000-0000-0000-0000-000000000001', 999, 'Dead', 74796, 'Live', 1) RETURNING id",
    ).fetch_one(&state.db).await.unwrap();

    // Confirm → remapped + marked confirmed.
    assert!(backend::import::confirm_suggestion(&state, common::uid(1), sug_id).await.unwrap());
    let status: String = sqlx::query_scalar("SELECT status FROM app.import_match WHERE id=$1")
        .bind(sug_id).fetch_one(&state.db).await.unwrap();
    assert_eq!(status, "confirmed");
    let live_present: i64 = sqlx::query_scalar("SELECT count(*) FROM app.user_show WHERE user_id='00000000-0000-0000-0000-000000000001' AND series_id=74796 AND NOT unavailable")
        .fetch_one(&state.db).await.unwrap();
    assert_eq!(live_present, 1, "dead series should now be the live one, visible");
    let ep: Option<i64> = sqlx::query_scalar("SELECT episode_id FROM app.watch_event WHERE user_id='00000000-0000-0000-0000-000000000001' AND series_id=74796")
        .fetch_one(&state.db).await.unwrap();
    assert_eq!(ep, Some(111), "watch event remapped to the live episode");

    // Confirming again is a no-op (already confirmed → not pending).
    assert!(!backend::import::confirm_suggestion(&state, common::uid(1), sug_id).await.unwrap());

    // A second dead series with a suggestion we reject.
    common::insert_series(&state.db, 888, "Dead2", None, None, None, None, serde_json::json!({})).await;
    common::follow(&state.db, 1, 888, true, false).await;
    common::set_user_show(&state.db, 1, 888, "unavailable", "true").await;
    let rej_id: i64 = sqlx::query_scalar(
        "INSERT INTO app.import_match (user_id, dead_series_id, import_name, suggested_series_id, distance) \
         VALUES ('00000000-0000-0000-0000-000000000001', 888, 'Dead2', 74796, 2) RETURNING id",
    ).fetch_one(&state.db).await.unwrap();
    assert!(backend::import::reject_suggestion(&state, common::uid(1), rej_id).await.unwrap());
    let (status2, still_hidden): (String, bool) = (
        sqlx::query_scalar("SELECT status FROM app.import_match WHERE id=$1").bind(rej_id).fetch_one(&state.db).await.unwrap(),
        sqlx::query_scalar("SELECT unavailable FROM app.user_show WHERE user_id='00000000-0000-0000-0000-000000000001' AND series_id=888").fetch_one(&state.db).await.unwrap(),
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

    tracking::delete_account(&state, common::uid(1)).await.unwrap();

    let users: i64 = sqlx::query_scalar("SELECT count(*) FROM app.users WHERE id='00000000-0000-0000-0000-000000000001'").fetch_one(&state.db).await.unwrap();
    let shows: i64 = sqlx::query_scalar("SELECT count(*) FROM app.user_show WHERE user_id='00000000-0000-0000-0000-000000000001'").fetch_one(&state.db).await.unwrap();
    let events: i64 = sqlx::query_scalar("SELECT count(*) FROM app.watch_event WHERE user_id='00000000-0000-0000-0000-000000000001'").fetch_one(&state.db).await.unwrap();
    assert_eq!((users, shows, events), (0, 0, 0));

    // Catalog (shared cache) is untouched by an account deletion.
    let series: i64 = sqlx::query_scalar("SELECT count(*) FROM catalog.series WHERE id=300").fetch_one(&state.db).await.unwrap();
    assert_eq!(series, 1);
}

/// Another user's library/shows are only reachable when the profile is public,
/// the viewer is an ACCEPTED follower, or it's your own — a pending request is not
/// enough. Guards the privacy gate that every `/api/users/:id/...` content
/// endpoint (library, shows, movies, stats, filter) relies on.
#[tokio::test]
async fn other_user_library_privacy_gate() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    let viewer = common::uid(1);
    let owner = common::uid(2);
    common::insert_user(&state.db, 1, "viewer@test.local").await;
    common::insert_user(&state.db, 2, "owner@test.local").await;
    // Owner is private and tracks one show.
    sqlx::query("UPDATE app.users SET is_private = true WHERE id = $1").bind(owner).execute(&state.db).await.unwrap();
    common::insert_series(&state.db, 100, "OwnersShow", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 2, 100, true, false).await;

    let langs = langs();
    let lib_total = |lib: &tracking::Library| {
        lib.watching.len() + lib.not_started.len() + lib.up_to_date.len() + lib.stale.len() + lib.for_later.len() + lib.stopped.len()
    };

    // Private + no relationship: invisible, and the content endpoints return empty.
    assert!(!tracking::profile_visible(&state, viewer, owner).await.unwrap());
    assert_eq!(lib_total(&tracking::user_library(&state, viewer, owner, &langs).await.unwrap()), 0, "private library must be hidden");
    assert!(tracking::user_shows(&state, viewer, owner, &langs).await.unwrap().is_empty());

    // A PENDING follow request does NOT grant access.
    sqlx::query("INSERT INTO app.user_follow (follower_id, followee_id, status) VALUES ($1,$2,'pending')")
        .bind(viewer).bind(owner).execute(&state.db).await.unwrap();
    assert!(!tracking::profile_visible(&state, viewer, owner).await.unwrap(), "a pending request must not grant access");

    // Accepted follow grants access.
    sqlx::query("UPDATE app.user_follow SET status='accepted' WHERE follower_id=$1 AND followee_id=$2")
        .bind(viewer).bind(owner).execute(&state.db).await.unwrap();
    assert!(tracking::profile_visible(&state, viewer, owner).await.unwrap());
    assert_eq!(lib_total(&tracking::user_library(&state, viewer, owner, &langs).await.unwrap()), 1, "accepted follower sees the owner's show");

    // Public profile is visible to anyone, even with no follow at all.
    sqlx::query("DELETE FROM app.user_follow WHERE follower_id=$1 AND followee_id=$2").bind(viewer).bind(owner).execute(&state.db).await.unwrap();
    sqlx::query("UPDATE app.users SET is_private = false WHERE id = $1").bind(owner).execute(&state.db).await.unwrap();
    assert!(tracking::profile_visible(&state, viewer, owner).await.unwrap(), "a public profile is visible to anyone");

    // Your own profile is always visible.
    assert!(tracking::profile_visible(&state, owner, owner).await.unwrap());
}

/// The activity timeline's visibility gate: `activity_visibility` narrows access on
/// top of the profile privacy gate. Default is 'friends' (accepted followers only),
/// 'everyone' opens it to anyone who can see the profile, 'only_me' closes it to all
/// but the owner — and a private profile still wins over an open activity setting.
#[tokio::test]
async fn activity_visibility_gate() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;

    let viewer = common::uid(1);
    let owner = common::uid(2);
    common::insert_user(&state.db, 1, "aviewer@test.local").await;
    common::insert_user(&state.db, 2, "aowner@test.local").await;

    // The owner (public profile) watched one episode.
    common::insert_series(&state.db, 100, "OwnersShow", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::insert_episode(&state.db, 1001, 100, 1, 1, "2020-01-01", "Pilot").await;
    common::watch_ago(&state.db, 2, 100, 1001, "w-a1", 1).await;

    let seen = async |me, target| tracking::user_activity(&state, me, target, &langs(), None, None).await.unwrap().len();

    // New accounts default to 'friends' (migration 0043), so a stranger sees nothing
    // even though the profile itself is public.
    let default_setting: String = sqlx::query_scalar("SELECT activity_visibility FROM app.users WHERE id = $1")
        .bind(owner).fetch_one(&state.db).await.unwrap();
    assert_eq!(default_setting, "friends", "activity defaults to friends-only");
    assert!(!tracking::activity_visible(&state, viewer, owner).await.unwrap());
    assert_eq!(seen(viewer, owner).await, 0, "a non-follower must not see friends-only activity");

    // Owner is always able to see their own, whatever the setting.
    assert!(tracking::activity_visible(&state, owner, owner).await.unwrap());
    assert_eq!(seen(owner, owner).await, 1);

    // A PENDING request is not a friend.
    common::user_follow(&state.db, 1, 2, "pending").await;
    assert!(!tracking::activity_visible(&state, viewer, owner).await.unwrap(), "pending request is not a friend");

    // Accepted follow → friend → visible.
    common::user_follow(&state.db, 1, 2, "accepted").await;
    assert!(tracking::activity_visible(&state, viewer, owner).await.unwrap());
    assert_eq!(seen(viewer, owner).await, 1);

    // 'only_me' closes it even to an accepted follower.
    common::set_activity_visibility(&state.db, 2, "only_me").await;
    assert!(!tracking::activity_visible(&state, viewer, owner).await.unwrap());
    assert_eq!(seen(viewer, owner).await, 0, "only_me hides activity from friends too");
    assert_eq!(seen(owner, owner).await, 1, "…but never from the owner");

    // 'everyone' opens it to a viewer with no follow at all.
    sqlx::query("DELETE FROM app.user_follow WHERE follower_id=$1 AND followee_id=$2")
        .bind(viewer).bind(owner).execute(&state.db).await.unwrap();
    common::set_activity_visibility(&state.db, 2, "everyone").await;
    assert!(tracking::activity_visible(&state, viewer, owner).await.unwrap());
    assert_eq!(seen(viewer, owner).await, 1, "everyone is visible without following");

    // The PROFILE gate still wins: private + 'everyone' is invisible to a non-follower.
    sqlx::query("UPDATE app.users SET is_private = true WHERE id = $1").bind(owner).execute(&state.db).await.unwrap();
    assert!(!tracking::activity_visible(&state, viewer, owner).await.unwrap(), "private profile overrides 'everyone'");
    assert_eq!(seen(viewer, owner).await, 0);

    // A user who hid their activity also drops out of their followers' feed.
    sqlx::query("UPDATE app.users SET is_private = false WHERE id = $1").bind(owner).execute(&state.db).await.unwrap();
    common::user_follow(&state.db, 1, 2, "accepted").await;
    assert_eq!(tracking::feed(&state, viewer).await.unwrap().len(), 1, "an 'everyone' friend shows in the feed");
    common::set_activity_visibility(&state.db, 2, "only_me").await;
    assert!(tracking::feed(&state, viewer).await.unwrap().is_empty(), "only_me removes them from the feed");
}

/// The timeline itself: episodes and movies interleaved newest-first, carrying the
/// fields the UI renders, and paging with limit/offset.
#[tokio::test]
async fn activity_lists_episodes_and_movies_newest_first() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "timeline@test.local").await;
    let me = common::uid(1);

    common::insert_series(&state.db, 10, "The Show", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::insert_episode(&state.db, 101, 10, 2, 5, "2021-03-04", "The Episode").await;
    common::insert_movie(&state.db, 500, "The Movie", Some(1999), Some(120)).await;

    // Oldest → newest: movie (5d), episode s2e5 (2d).
    common::watch_movie_ago(&state.db, 1, 500, "w-movie", 5).await;
    common::watch_se(&state.db, 1, 10, 101, 2, 5, "w-ep").await; // now

    let items = tracking::activity(&state, me, &langs(), 30, 0).await.unwrap();
    assert_eq!(items.len(), 2);

    // Newest first: the episode.
    let ep = &items[0];
    assert_eq!(ep.entity_type, "episode");
    assert_eq!(ep.series_id, Some(10));
    assert_eq!(ep.name.as_deref(), Some("The Show"));
    assert_eq!(ep.episode_name.as_deref(), Some("The Episode"));
    assert_eq!((ep.season_number, ep.episode_number), (Some(2), Some(5)));
    assert!(ep.watched_at.is_some());

    let mv = &items[1];
    assert_eq!(mv.entity_type, "movie");
    assert_eq!(mv.movie_id, Some(500));
    assert_eq!(mv.name.as_deref(), Some("The Movie"), "movies resolve their own title, not the series join");
    assert!(mv.series_id.is_none() && mv.episode_id.is_none());

    // Paging: limit/offset walk the same ordering without repeats.
    let page1 = tracking::activity(&state, me, &langs(), 1, 0).await.unwrap();
    let page2 = tracking::activity(&state, me, &langs(), 1, 1).await.unwrap();
    assert_eq!(page1.len(), 1);
    assert_eq!(page2.len(), 1);
    assert_eq!(page1[0].id, ep.id);
    assert_eq!(page2[0].id, mv.id);

    // Titles follow the VIEWER's language preference.
    sqlx::query("INSERT INTO catalog.translation (entity_type, entity_id, language, name) VALUES ('series',10,'fra','La Série')")
        .execute(&state.db).await.unwrap();
    let fr = tracking::activity(&state, me, &["fra".to_string(), "eng".to_string()], 30, 0).await.unwrap();
    assert_eq!(fr[0].name.as_deref(), Some("La Série"));
}

/// A caught-up show moves to WATCHING (not STALE) when a fresh episode airs, even
/// if the viewer's last watch was long ago — recency of new content counts, not
/// just when they last watched. A backlog with only old episodes stays STALE.
#[tokio::test]
async fn new_episode_keeps_show_in_watching_not_stale() {
    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "recency@test.local").await;

    // Ep 1 aired 60 days ago and was watched then; a NEW ep 2 aired 3 days ago, unwatched.
    common::insert_series(&state.db, 10, "Recency", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 10, true, false).await;
    common::set_user_show(&state.db, 1, 10, "nb_episodes_seen", "1").await;
    common::insert_episode_in_days(&state.db, 101, 10, 1, 1, -60, "Ep1").await;
    common::insert_episode_in_days(&state.db, 102, 10, 1, 2, -3, "Ep2").await;
    common::watch_ago(&state.db, 1, 10, 101, "w-ep1", 60).await;

    let lib = tracking::library(&state, common::uid(1), &langs(), "popularity", true).await.unwrap();
    assert_eq!(lib.watching.iter().filter(|s| s.series_id == 10).count(), 1, "fresh episode -> Watching");
    assert!(lib.stale.iter().all(|s| s.series_id != 10), "not Stale when a new episode aired recently");

    // Control: behind, but the newest episode is also old (aired 80 days ago) -> Stale.
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "recency@test.local").await;
    common::insert_series(&state.db, 20, "Backlog", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 20, true, false).await;
    common::set_user_show(&state.db, 1, 20, "nb_episodes_seen", "1").await;
    common::insert_episode_in_days(&state.db, 201, 20, 1, 1, -90, "Ep1").await;
    common::insert_episode_in_days(&state.db, 202, 20, 1, 2, -80, "Ep2").await;
    common::watch_ago(&state.db, 1, 20, 201, "w-ep1", 60).await;

    let lib2 = tracking::library(&state, common::uid(1), &langs(), "popularity", true).await.unwrap();
    assert_eq!(lib2.stale.iter().filter(|s| s.series_id == 20).count(), 1, "old backlog -> Stale");
}

/// The Library layout: a user who has never customized gets the built-in defaults,
/// a saved layout round-trips (order, hidden sections, custom filters), and a
/// built-in introduced after they customized is appended disabled rather than
/// silently reappearing in the middle of their Library.
#[tokio::test]
async fn library_sections_round_trip_and_default() {
    use backend::tracking::sections::{self, LibrarySection};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "layout@test.local").await;
    let me = common::uid(1);

    // Never customized -> every built-in, enabled, in default order.
    let defaults = sections::library_sections(&state, me).await.unwrap();
    assert_eq!(defaults.len(), sections::BUILTIN_SECTIONS.len());
    assert!(defaults.iter().all(|s| s.enabled && s.builtin.is_some()));
    assert_eq!(defaults[0].builtin.as_deref(), Some("watching"));

    // Save a reordered layout: one built-in hidden, one dropped entirely, and a
    // custom section carrying its own filter.
    let custom = LibrarySection {
        id: None,
        builtin: None,
        title: Some("Comfort anime".into()),
        filters: Some(serde_json::json!({"type": "anime", "sort": "my_rating", "favorites": "true"})),
        enabled: true,
    };
    let saved = sections::set_library_sections(
        &state,
        me,
        &[
            custom.clone(),
            LibrarySection { id: None, builtin: Some("watching".into()), title: None, filters: None, enabled: true },
            LibrarySection { id: None, builtin: Some("stopped".into()), title: None, filters: None, enabled: false },
        ],
    )
    .await
    .unwrap();

    // Order is the payload: the custom rail comes first, as sent.
    assert_eq!(saved[0].title.as_deref(), Some("Comfort anime"));
    assert_eq!(saved[0].filters.as_ref().unwrap()["type"], "anime");
    assert!(saved[0].id.is_some(), "the server assigns an id to a new section");
    assert_eq!(saved[1].builtin.as_deref(), Some("watching"));
    assert_eq!(saved[2].builtin.as_deref(), Some("stopped"));
    assert!(!saved[2].enabled, "a hidden section keeps its place in the order");

    // Built-ins the saved layout never mentioned are appended DISABLED, so they
    // surface in the customize sheet without rearranging the user's Library.
    let appended: Vec<_> = saved[3..].iter().map(|s| s.builtin.clone().unwrap()).collect();
    assert!(appended.contains(&"movies".to_string()));
    assert!(saved[3..].iter().all(|s| !s.enabled), "newly-surfaced built-ins stay off");

    // Reading it back gives the same thing (ids preserved, no duplicate rows).
    let reread = sections::library_sections(&state, me).await.unwrap();
    assert_eq!(reread.len(), saved.len());
    assert_eq!(reread[0].id, saved[0].id, "ids are stable across reads");

    // Re-saving with the assigned id keeps that id rather than minting a new row.
    let edited = LibrarySection { title: Some("Comfort shows".into()), ..saved[0].clone() };
    let resaved = sections::set_library_sections(&state, me, &[edited]).await.unwrap();
    assert_eq!(resaved[0].id, saved[0].id, "editing preserves the section id");
    assert_eq!(resaved[0].title.as_deref(), Some("Comfort shows"));

    // A rejected save leaves the stored layout untouched.
    let bad = vec![LibrarySection { id: None, builtin: Some("not_a_category".into()), title: None, filters: None, enabled: true }];
    assert!(sections::set_library_sections(&state, me, &bad).await.is_err());
    let after = sections::library_sections(&state, me).await.unwrap();
    assert_eq!(after[0].title.as_deref(), Some("Comfort shows"), "a rejected save must not clobber the layout");
}

/// The batched library filter must return exactly what the per-section endpoint
/// would, key by key — it's an optimization, so any behavioural difference is a bug.
#[tokio::test]
async fn library_filter_batch_matches_individual_queries() {
    use backend::catalog::discover::{search_db, Filters};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "batch@test.local").await;
    let me = common::uid(1);

    // Two series (one anime) and a movie, all tracked.
    common::insert_series(&state.db, 700, "Batch Drama", Some(2020), Some(45), Some(9.0), Some("eng"), serde_json::json!({})).await;
    common::insert_series(&state.db, 701, "Batch Anime", Some(2021), Some(24), Some(8.0), Some("jpn"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 700, true, false).await;
    common::follow(&state.db, 1, 701, true, false).await;

    // Each kind on its own, the way one batch entry per (section, kind) would run.
    let run = async |kind: &str| {
        search_db(
            &state,
            &Filters {
                kind: kind.to_string(),
                library_user: Some(me),
                viewer: Some(me),
                sort: "name".into(),
                sort_desc: false,
                limit: 30,
                ..Default::default()
            },
            &langs(),
        )
        .await
        .unwrap()
    };

    let series = run("series").await;
    let anime = run("anime").await;
    assert_eq!(series.len(), 2, "a series query carries anime too");
    assert_eq!(anime.len(), 1, "anime narrows to Japanese-language series");

    // is_anime is what lets a multi-kind section drop anime it didn't ask for.
    assert!(series.iter().any(|r| r.is_anime), "the anime row is flagged");
    assert!(series.iter().any(|r| !r.is_anime), "the non-anime row is not");
    assert!(anime.iter().all(|r| r.is_anime));

    // Running the same filter twice is stable — the batch relies on that, since it
    // runs entries concurrently and reassembles them by key.
    assert_eq!(
        run("series").await.iter().map(|r| r.tvdb_id).collect::<Vec<_>>(),
        series.iter().map(|r| r.tvdb_id).collect::<Vec<_>>(),
    );
}

/// The property the shared SQL classification exists to guarantee: the bucket a
/// show lands in on the Library rails is EXACTLY what `state=<bucket>` returns from
/// the filter endpoint. If these ever disagree, a duplicated category silently
/// stops matching the category it was copied from.
#[tokio::test]
async fn library_rails_and_state_filter_agree() {
    use backend::catalog::discover::{search_db, Filters};
    use backend::tracking::state::STATES;

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "states@test.local").await;
    let me = common::uid(1);

    // One show per bucket, built the way each bucket actually arises.
    let mk = async |id: i64, name: &str| {
        common::insert_series(&state.db, id, name, Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
        common::follow(&state.db, 1, id, true, false).await;
    };

    // watching: behind, with a recent watch.
    mk(800, "Watching").await;
    common::insert_episode_in_days(&state.db, 8001, 800, 1, 1, -20, "E1").await;
    common::insert_episode_in_days(&state.db, 8002, 800, 1, 2, -10, "E2").await;
    common::watch_ago(&state.db, 1, 800, 8001, "w-800", 2).await;

    // stale: behind, nothing watched or aired for months.
    mk(801, "Stale").await;
    common::insert_episode_in_days(&state.db, 8011, 801, 1, 1, -300, "E1").await;
    common::insert_episode_in_days(&state.db, 8012, 801, 1, 2, -290, "E2").await;
    common::watch_ago(&state.db, 1, 801, 8011, "w-801", 200).await;

    // up_to_date: seen the latest aired episode.
    mk(802, "UpToDate").await;
    common::insert_episode_in_days(&state.db, 8021, 802, 1, 1, -40, "E1").await;
    common::watch_ago(&state.db, 1, 802, 8021, "w-802", 5).await;

    // not_started: tracked, nothing watched.
    mk(803, "NotStarted").await;
    common::insert_episode_in_days(&state.db, 8031, 803, 1, 1, -40, "E1").await;

    // for_later and stopped are set by status/archived, whatever the progress.
    mk(804, "ForLater").await;
    common::set_user_show(&state.db, 1, 804, "status", "'for_later'").await;
    mk(805, "Stopped").await;
    common::set_user_show(&state.db, 1, 805, "archived", "true").await;

    let lib = tracking::library(&state, me, &langs(), "name", false).await.unwrap();
    let rails: Vec<(&str, Vec<i64>)> = vec![
        ("watching", lib.watching.iter().map(|s| s.series_id).collect()),
        ("stale", lib.stale.iter().map(|s| s.series_id).collect()),
        ("up_to_date", lib.up_to_date.iter().map(|s| s.series_id).collect()),
        ("not_started", lib.not_started.iter().map(|s| s.series_id).collect()),
        ("for_later", lib.for_later.iter().map(|s| s.series_id).collect()),
        ("stopped", lib.stopped.iter().map(|s| s.series_id).collect()),
    ];
    // The fixtures are meant to cover every bucket — a plan change that empties one
    // would otherwise make this test pass vacuously.
    for (name, ids) in &rails {
        assert!(!ids.is_empty(), "fixture for '{name}' produced no rows");
    }

    for (bucket, mut rail_ids) in rails {
        let mut filtered: Vec<i64> = search_db(
            &state,
            &Filters {
                kind: "series".into(),
                library_user: Some(me),
                viewer: Some(me),
                states: vec![bucket.to_string()],
                sort: "name".into(),
                limit: 200,
                ..Default::default()
            },
            &langs(),
        )
        .await
        .unwrap()
        .into_iter()
        .filter_map(|r| r.tvdb_id)
        .collect();
        rail_ids.sort();
        filtered.sort();
        assert_eq!(filtered, rail_ids, "rail and state filter disagree for '{bucket}'");
    }

    // Any-of: asking for two buckets returns their union, and every bucket name the
    // classification can emit is accepted by the filter.
    let both = search_db(
        &state,
        &Filters {
            kind: "series".into(),
            library_user: Some(me),
            viewer: Some(me),
            states: vec!["for_later".into(), "stopped".into()],
            limit: 200,
            ..Default::default()
        },
        &langs(),
    )
    .await
    .unwrap();
    assert_eq!(both.len(), 2, "state is any-of");
    assert_eq!(STATES.len(), 6, "every bucket above is covered");
}

/// The Library filter must scope movies through `user_movie`. Series and movie ids
/// overlap in TheTVDB, so joining `user_show` on a movie id matched unrelated
/// titles — a library of 17 movies returned 171.
#[tokio::test]
async fn library_filter_scopes_movies_by_movie_membership() {
    use backend::catalog::discover::{search_db, Filters};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "movscope@test.local").await;
    let me = common::uid(1);

    // A movie the user does NOT track, whose id collides with a series they DO.
    let colliding_id = 900_i64;
    common::insert_series(&state.db, colliding_id, "Tracked Series", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, colliding_id, true, false).await;
    common::insert_movie(&state.db, colliding_id, "Untracked Movie", Some(2019), Some(100)).await;

    let movies = search_db(
        &state,
        &Filters { kind: "movie".into(), library_user: Some(me), viewer: Some(me), limit: 50, ..Default::default() },
        &langs(),
    )
    .await
    .unwrap();
    assert!(
        movies.is_empty(),
        "a movie sharing an id with a tracked SERIES must not appear in the movie library"
    );
}

/// Anime shares the series table, so `type=series` returns it. A section that wants
/// series but NOT anime must have it excluded IN SQL — filtering client-side runs
/// after LIMIT, which empties a rail whose top results all happen to be anime.
#[tokio::test]
async fn exclude_anime_applies_before_the_limit() {
    use backend::catalog::discover::{search_db, Filters};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "noanime@test.local").await;
    let me = common::uid(1);

    // Three anime sort ahead of the one live-action show (by name), so a limit of 3
    // would return only anime if the exclusion happened afterwards.
    for (id, name) in [(910, "AAA Anime"), (911, "BBB Anime"), (912, "CCC Anime")] {
        common::insert_series(&state.db, id, name, Some(2020), Some(24), Some(1.0), Some("jpn"), serde_json::json!({})).await;
        common::follow(&state.db, 1, id, true, false).await;
    }
    common::insert_series(&state.db, 913, "ZZZ Drama", Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 913, true, false).await;
    // An unknown original language is NOT anime and must survive the exclusion.
    common::insert_series(&state.db, 914, "ZZZ Unknown", Some(2020), Some(45), Some(1.0), None, serde_json::json!({})).await;
    common::follow(&state.db, 1, 914, true, false).await;

    let run = async |exclude_anime: bool, limit: i64| {
        search_db(
            &state,
            &Filters {
                kind: "series".into(),
                library_user: Some(me),
                viewer: Some(me),
                sort: "name".into(),
                sort_desc: false,
                limit,
                exclude_anime,
                ..Default::default()
            },
            &langs(),
        )
        .await
        .unwrap()
    };

    // Without the flag, a series query carries anime — that's the trap.
    assert_eq!(run(false, 3).await.len(), 3);
    assert!(run(false, 3).await.iter().all(|r| r.is_anime), "the top 3 by name are all anime");

    // With it, the limit applies to the shows that actually qualify.
    let kept = run(true, 3).await;
    assert_eq!(kept.len(), 2, "only the non-anime shows remain");
    assert!(kept.iter().all(|r| !r.is_anime));
    let names: Vec<_> = kept.iter().filter_map(|r| r.name.as_deref()).collect();
    assert!(names.contains(&"ZZZ Drama"));
    assert!(names.contains(&"ZZZ Unknown"), "unknown original language is not anime");
}

/// A custom rail shows every matching title, like the built-in rails — not a page
/// of 30. The old default silently truncated a rail whose match count exceeded it.
#[tokio::test]
async fn a_library_rail_is_not_capped_at_a_page() {
    use backend::catalog::discover::{search_db, Filters};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "nocap@test.local").await;
    let me = common::uid(1);

    // More shows than the old per-rail default.
    for i in 0..45_i64 {
        let id = 3000 + i;
        common::insert_series(&state.db, id, &format!("Show {i:02}"), Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
        common::follow(&state.db, 1, id, true, false).await;
    }

    let all = search_db(
        &state,
        &Filters {
            kind: "series".into(),
            library_user: Some(me),
            viewer: Some(me),
            // What the batch handler passes when the client sends no limit.
            limit: 2000,
            ..Default::default()
        },
        &langs(),
    )
    .await
    .unwrap();
    assert_eq!(all.len(), 45, "the rail returns the whole match set");

    // Discover stays capped: it browses the entire catalog, where an unbounded
    // limit would be a very different proposition.
    let discovered = search_db(
        &state,
        &Filters { kind: "series".into(), viewer: Some(me), limit: 2000, ..Default::default() },
        &langs(),
    )
    .await
    .unwrap();
    assert!(discovered.len() <= 200, "catalog-wide queries keep the tight ceiling");
}

/// The exact filter map the client stores for an anime rail, driven through the
/// batch endpoint's parsing path (query-map -> DiscoverQuery -> Filters) and then
/// the query — reproducing a rail that came back empty in the app.
#[tokio::test]
async fn anime_rail_filter_map_round_trips_and_returns_rows() {
    use backend::catalog::discover::search_db;

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "animerail@test.local").await;
    let me = common::uid(1);

    common::insert_series(&state.db, 950, "Anime One", Some(2021), Some(24), Some(8.0), Some("jpn"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 950, true, false).await;
    common::insert_episode_in_days(&state.db, 9501, 950, 1, 1, -30, "E1").await;
    common::watch_ago(&state.db, 1, 950, 9501, "w-950", 3).await;

    // Exactly what `app.library_section.filters` holds for the failing rail.
    let stored = "dir=desc&sort=last_watched&type=anime";
    let q: backend::web::handlers::discover::DiscoverQuery =
        serde_urlencoded::from_str(stored).expect("the stored map must parse as a DiscoverQuery");
    assert_eq!(q.kind.as_deref(), Some("anime"), "`type` must map onto `kind`");
    assert_eq!(q.sort.as_deref(), Some("last_watched"));

    let filters = backend::web::handlers::discover::build_filters(&q, Some(me), None, Some(me));
    assert_eq!(filters.kind, "anime");
    assert_eq!(filters.sort, "last_watched");
    assert_eq!(filters.limit, 120, "an unset limit falls back to the default");

    let rows = search_db(&state, &filters, &langs()).await.unwrap();
    assert_eq!(rows.len(), 1, "the anime rail must return the tracked anime");
}

/// A watch-recency SORT pulls in the same CTEs a state filter needs — but it must
/// not also apply the state predicate. Emitting `= ANY('{}')` for a sort-only rail
/// matched nothing, so a category sorted by "last watched" rendered empty.
#[tokio::test]
async fn a_watch_recency_sort_alone_does_not_filter_by_state() {
    use backend::catalog::discover::{search_db, Filters};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "sortonly@test.local").await;
    let me = common::uid(1);

    // Deliberately spread across buckets: never-watched, recently watched, stopped.
    for (id, name) in [(960, "Never"), (961, "Recent"), (962, "Stopped")] {
        common::insert_series(&state.db, id, name, Some(2020), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
        common::follow(&state.db, 1, id, true, false).await;
        common::insert_episode_in_days(&state.db, id * 10, id, 1, 1, -40, "E1").await;
    }
    common::watch_ago(&state.db, 1, 961, 9610, "w-961", 2).await;
    common::set_user_show(&state.db, 1, 962, "archived", "true").await;

    let by_recency = search_db(
        &state,
        &Filters {
            kind: "series".into(),
            library_user: Some(me),
            viewer: Some(me),
            sort: "last_watched".into(),
            limit: 100,
            ..Default::default() // states is EMPTY
        },
        &langs(),
    )
    .await
    .unwrap();
    assert_eq!(by_recency.len(), 3, "no state filter was asked for, so nothing is filtered out");
    assert_eq!(by_recency[0].name.as_deref(), Some("Recent"), "and it is actually sorted by recency");

    // Combining the two still narrows properly.
    let stopped_only = search_db(
        &state,
        &Filters {
            kind: "series".into(),
            library_user: Some(me),
            viewer: Some(me),
            sort: "last_watched".into(),
            states: vec!["stopped".into()],
            limit: 100,
            ..Default::default()
        },
        &langs(),
    )
    .await
    .unwrap();
    assert_eq!(stopped_only.len(), 1);
    assert_eq!(stopped_only[0].name.as_deref(), Some("Stopped"));
}

/// The watch-history facets, and the view they exist for: "shows I've watched in
/// the last N days, still running, most left to watch first".
#[tokio::test]
async fn watch_history_facets_and_the_seen_recently_view() {
    use backend::catalog::discover::{search_db, Filters};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "facets@test.local").await;
    let me = common::uid(1);

    // A running show watched recently, 3 of 5 aired episodes left.
    common::insert_series(&state.db, 970, "Running Behind", Some(2024), Some(24), Some(8.0), Some("eng"), serde_json::json!({"status": "Continuing"})).await;
    sqlx::query("UPDATE catalog.series SET status='Continuing' WHERE id=970").execute(&state.db).await.unwrap();
    common::follow(&state.db, 1, 970, true, false).await;
    for (n, days) in [(1, -50), (2, -40), (3, -30), (4, -20), (5, -10)] {
        common::insert_episode_in_days(&state.db, 9700 + n, 970, 1, n as i32, days, &format!("E{n}")).await;
    }
    common::watch_ago(&state.db, 1, 970, 9701, "w-970-1", 4).await;
    common::watch_ago(&state.db, 1, 970, 9702, "w-970-2", 3).await;
    // ...and one future episode, so it also has something upcoming.
    common::insert_episode_in_days(&state.db, 9709, 970, 1, 6, 14, "E6").await;

    // A running show watched recently with only 1 left.
    sqlx::query("UPDATE catalog.series SET status='Continuing' WHERE id=971").execute(&state.db).await.ok();
    common::insert_series(&state.db, 971, "Nearly Caught Up", Some(2024), Some(24), Some(8.0), Some("eng"), serde_json::json!({})).await;
    sqlx::query("UPDATE catalog.series SET status='Continuing' WHERE id=971").execute(&state.db).await.unwrap();
    common::follow(&state.db, 1, 971, true, false).await;
    common::insert_episode_in_days(&state.db, 9711, 971, 1, 1, -30, "E1").await;
    common::insert_episode_in_days(&state.db, 9712, 971, 1, 2, -20, "E2").await;
    common::watch_ago(&state.db, 1, 971, 9711, "w-971-1", 2).await;

    // An ENDED show, watched recently — must be excluded by the status facet.
    common::insert_series(&state.db, 972, "Finished Long Ago", Some(2010), Some(24), Some(8.0), Some("eng"), serde_json::json!({})).await;
    sqlx::query("UPDATE catalog.series SET status='Ended' WHERE id=972").execute(&state.db).await.unwrap();
    common::follow(&state.db, 1, 972, true, false).await;
    common::insert_episode_in_days(&state.db, 9721, 972, 1, 1, -900, "E1").await;
    common::watch_ago(&state.db, 1, 972, 9721, "w-972-1", 1).await;

    // A running show NOT watched for a year — excluded by the recency facet.
    common::insert_series(&state.db, 973, "Long Abandoned", Some(2015), Some(24), Some(8.0), Some("eng"), serde_json::json!({})).await;
    sqlx::query("UPDATE catalog.series SET status='Continuing' WHERE id=973").execute(&state.db).await.unwrap();
    common::follow(&state.db, 1, 973, true, false).await;
    common::insert_episode_in_days(&state.db, 9731, 973, 1, 1, -800, "E1").await;
    common::insert_episode_in_days(&state.db, 9732, 973, 1, 2, -700, "E2").await;
    common::watch_ago(&state.db, 1, 973, 9731, "w-973-1", 365).await;

    let base = || Filters {
        kind: "series".into(),
        library_user: Some(me),
        viewer: Some(me),
        limit: 100,
        ..Default::default()
    };
    let names = |rows: Vec<backend::catalog::SearchResult>| {
        rows.into_iter().filter_map(|r| r.name).collect::<Vec<_>>()
    };

    // THE VIEW: watched in the last 30 days + still running + most remaining first.
    let view = search_db(
        &state,
        &Filters {
            watched_days_max: Some(30),
            statuses: vec!["Continuing".into()],
            sort: "remaining".into(),
            sort_desc: true,
            ..base()
        },
        &langs(),
    )
    .await
    .unwrap();
    assert_eq!(
        names(view),
        vec!["Running Behind", "Nearly Caught Up"],
        "recent + running, ordered by how much is left"
    );

    // Each facet on its own.
    let stale_side = search_db(&state, &Filters { watched_days_min: Some(90), ..base() }, &langs()).await.unwrap();
    assert_eq!(names(stale_side), vec!["Long Abandoned"], "untouched for at least 90 days");

    let leftovers = search_db(&state, &Filters { remaining_min: Some(2), ..base() }, &langs()).await.unwrap();
    assert!(names(leftovers).contains(&"Running Behind".to_string()));

    let half_done = search_db(&state, &Filters { progress_max: Some(50.0), ..base() }, &langs()).await.unwrap();
    assert!(names(half_done).contains(&"Running Behind".to_string()), "2 of 5 seen is 40%");

    let upcoming = search_db(&state, &Filters { has_upcoming: Some(true), ..base() }, &langs()).await.unwrap();
    assert_eq!(names(upcoming), vec!["Running Behind"], "only that one has a future episode");

    let everything_released = search_db(&state, &Filters { has_upcoming: Some(false), ..base() }, &langs()).await.unwrap();
    assert!(!names(everything_released).contains(&"Running Behind".to_string()));

    let done = search_db(&state, &Filters { caught_up: Some(true), ..base() }, &langs()).await.unwrap();
    assert!(names(done).contains(&"Finished Long Ago".to_string()), "seen its only episode");

    // Ascending order = fewest left first, the other reading of the same view.
    let fewest = search_db(
        &state,
        &Filters { watched_days_max: Some(30), statuses: vec!["Continuing".into()], sort: "remaining".into(), sort_desc: false, ..base() },
        &langs(),
    )
    .await
    .unwrap();
    assert_eq!(names(fewest), vec!["Nearly Caught Up", "Running Behind"]);
}

/// Each bound of a watch-history range applies independently, so a filter can be
/// half-open. A range that always sent both bounds silently excluded everything
/// past the slider's ceiling — "not watched in over 90 days" would have dropped a
/// show last watched two years ago, because it also asserted "within 365 days".
#[tokio::test]
async fn watch_history_ranges_are_half_open() {
    use backend::catalog::discover::{search_db, Filters};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "halfopen@test.local").await;
    let me = common::uid(1);

    // Watched two years ago — well beyond any slider ceiling.
    common::insert_series(&state.db, 980, "Ancient History", Some(2005), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 980, true, false).await;
    common::insert_episode_in_days(&state.db, 9801, 980, 1, 1, -1000, "E1").await;
    common::watch_ago(&state.db, 1, 980, 9801, "w-980", 730).await;

    // Watched last week.
    common::insert_series(&state.db, 981, "Just Watched", Some(2024), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 981, true, false).await;
    common::insert_episode_in_days(&state.db, 9811, 981, 1, 1, -30, "E1").await;
    common::watch_ago(&state.db, 1, 981, 9811, "w-981", 7).await;

    let base = || Filters { kind: "series".into(), library_user: Some(me), viewer: Some(me), limit: 100, ..Default::default() };
    let names = |rows: Vec<backend::catalog::SearchResult>| rows.into_iter().filter_map(|r| r.name).collect::<Vec<_>>();

    // Min only: "untouched for at least 90 days" — must reach back indefinitely.
    let old = search_db(&state, &Filters { watched_days_min: Some(90), ..base() }, &langs()).await.unwrap();
    assert_eq!(names(old), vec!["Ancient History"], "a two-year-old watch is still 'over 90 days ago'");

    // Max only: "within the last 30 days".
    let recent = search_db(&state, &Filters { watched_days_max: Some(30), ..base() }, &langs()).await.unwrap();
    assert_eq!(names(recent), vec!["Just Watched"]);

    // The same independence for the aired and remaining ranges.
    let aired_long_ago = search_db(&state, &Filters { aired_days_min: Some(365), ..base() }, &langs()).await.unwrap();
    assert_eq!(names(aired_long_ago), vec!["Ancient History"]);

    let anything_left = search_db(&state, &Filters { remaining_min: Some(0), ..base() }, &langs()).await.unwrap();
    assert_eq!(anything_left.len(), 2, "a min of 0 constrains nothing away");
}

/// A custom rail's cards draw a progress bar, so the search rows need the same
/// counts `LibraryShow` carries — and only when asked, since computing them costs
/// the watch-history aggregates.
#[tokio::test]
async fn search_rows_carry_progress_only_when_requested() {
    use backend::catalog::discover::{search_db, Filters};

    let _g = common::guard().await;
    let Some(state) = common::state().await else { return };
    common::clean(&state.db).await;
    common::insert_user(&state.db, 1, "progress@test.local").await;
    let me = common::uid(1);

    common::insert_series(&state.db, 990, "Half Watched", Some(2024), Some(45), Some(1.0), Some("eng"), serde_json::json!({})).await;
    common::follow(&state.db, 1, 990, true, false).await;
    for n in 1..=4_i64 {
        common::insert_episode_in_days(&state.db, 9900 + n, 990, 1, n as i32, -30, &format!("E{n}")).await;
    }
    common::watch_ago(&state.db, 1, 990, 9901, "w-990-1", 5).await;
    common::watch_ago(&state.db, 1, 990, 9902, "w-990-2", 4).await;

    let base = || Filters { kind: "series".into(), library_user: Some(me), viewer: Some(me), limit: 10, ..Default::default() };

    // Opt-in: what the batch endpoint asks for.
    let with = search_db(&state, &Filters { with_progress: true, ..base() }, &langs()).await.unwrap();
    assert_eq!(with[0].total_episodes, Some(4));
    assert_eq!(with[0].seen_episodes, Some(2), "2 of 4 aired episodes seen");

    // Off by default, so a paged search doesn't pay for aggregates it won't draw.
    let without = search_db(&state, &base(), &langs()).await.unwrap();
    assert_eq!(without[0].total_episodes, None);
    assert_eq!(without[0].seen_episodes, None, "absent, which the client renders as no bar");
}
