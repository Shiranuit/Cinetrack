//! The Library's category for a tracked title — "watching", "stale", "up to
//! date", … — as SQL, so there is exactly ONE definition of each bucket.
//!
//! It used to live in Rust, after [`crate::tracking::library`]'s query. That was
//! fine while the rails were the only consumer, but a custom Library section can
//! now filter on the same buckets, and two implementations of "stale" would drift
//! the moment either side was tuned. Both callers splice these fragments in:
//!
//! * [`crate::tracking::library`] selects [`STATE_CASE`] and groups on it;
//! * [`crate::catalog::discover::search_db`] exposes it as a filterable column.
//!
//! Each caller defines its own `lib` CTE (the candidate set — they select
//! different columns); [`watch_state_ctes`] supplies the derived ones on top.

/// The buckets, in the order a fresh Library shows them. These are also the values
/// the `state` filter accepts — see `sections::validate_filters`.
pub const STATES: [&str; 6] = ["watching", "stale", "not_started", "for_later", "up_to_date", "stopped"];

/// A started, un-caught-up show goes "stale" when neither a watch nor a new
/// episode has happened within this window.
pub const STALE_DAYS: i64 = 30;

/// The per-series aggregates the classification needs, for one user.
///
/// Expects a preceding CTE named `lib` exposing `series_id`, and `user_bind` to be
/// the placeholder holding the user id (e.g. `"$1"`). Emits `ep`, `latest_eps`,
/// `lw`, `seen` and `caught` — the caller joins them by `series_id`.
///
/// Scoped to `lib` throughout: every aggregate is bounded by the user's own
/// library, never the whole catalog.
pub fn watch_state_ctes(user_bind: &str) -> String {
    format!(
        "ep AS ( \
            SELECT e.series_id, \
                   count(*) FILTER (WHERE e.aired IS NULL OR e.aired <= current_date) AS total_episodes, \
                   max(e.aired) FILTER (WHERE e.aired IS NULL OR e.aired <= current_date) AS max_aired, \
                   COALESCE(bool_or(e.aired > current_date), false) AS has_upcoming \
            FROM catalog.episode e \
            WHERE e.series_id IN (SELECT series_id FROM lib) \
              AND NOT e.deleted AND e.season_number > 0 \
            GROUP BY e.series_id \
        ), \
        latest_eps AS ( \
            SELECT e.series_id, e.id AS episode_id FROM catalog.episode e \
            JOIN ep ON ep.series_id = e.series_id AND e.aired = ep.max_aired \
            WHERE NOT e.deleted AND e.season_number > 0 \
        ), \
        lw AS ( \
            SELECT w.series_id, max(w.watched_at) AS last_watched FROM app.watch_event w \
            WHERE w.user_id = {user_bind} AND w.series_id IN (SELECT series_id FROM lib) \
            GROUP BY w.series_id \
        ), \
        seen AS ( \
            SELECT w.series_id, count(DISTINCT w.episode_id) AS seen_episodes \
            FROM app.watch_event w \
            JOIN catalog.episode ce ON ce.id = w.episode_id AND ce.season_number > 0 \
            WHERE w.user_id = {user_bind} AND w.series_id IN (SELECT series_id FROM lib) \
            GROUP BY w.series_id \
        ), \
        caught AS ( \
            SELECT DISTINCT le.series_id FROM latest_eps le \
            JOIN app.watch_event w ON w.user_id = {user_bind} AND w.episode_id = le.episode_id \
        )"
    )
}

/// Seen the latest aired episode — with the fallback for shows whose episodes carry
/// no mirrored air date (no "latest aired" to have seen), where having seen every
/// counted episode is the best available answer.
///
/// Shared so the `caught_up` FILTER and [`state_case`] can't drift apart.
pub const CAUGHT_UP_EXPR: &str = "(caught.series_id IS NOT NULL \
     OR (COALESCE(ep.total_episodes, 0) > 0 AND COALESCE(seen.seen_episodes, 0) >= ep.total_episodes))";

/// Aired episodes you haven't watched. Floored at zero: watch rows can point at
/// episodes the catalog no longer holds, which would otherwise make this negative.
pub const REMAINING_EXPR: &str =
    "GREATEST(COALESCE(ep.total_episodes, 0) - COALESCE(seen.seen_episodes, 0), 0)";

/// Percent of aired episodes watched, or NULL when nothing has aired (a show with
/// no episodes has no meaningful progress, and must not read as 0%).
pub const PROGRESS_EXPR: &str =
    "(100.0 * COALESCE(seen.seen_episodes, 0) / NULLIF(ep.total_episodes, 0))";

/// Whether a future-dated episode is already on the schedule.
pub const HAS_UPCOMING_EXPR: &str = "COALESCE(ep.has_upcoming, false)";

/// The `LEFT JOIN`s pairing [`watch_state_ctes`] to a base row. `id_expr` is the
/// series id in the caller's FROM (e.g. `lib.series_id` or `x.id`).
pub fn watch_state_joins(id_expr: &str) -> String {
    format!(
        "LEFT JOIN ep ON ep.series_id = {id_expr} \
         LEFT JOIN lw ON lw.series_id = {id_expr} \
         LEFT JOIN seen ON seen.series_id = {id_expr} \
         LEFT JOIN caught ON caught.series_id = {id_expr}"
    )
}

/// Classify one row into a bucket. Order matters — the buckets are mutually
/// exclusive and the first match wins, which is what makes "Watching" mean
/// *behind, and active* rather than merely *watched recently*.
///
/// `tracking` is the alias holding `archived` / `status` / `nb_episodes_seen`
/// (the `user_show` columns), so each caller can name its `lib` CTE freely.
///
/// `keep_upcoming` is the user's `keep_upcoming_in_to_watch` preference (migration
/// 0045). It narrows ONE arm: "Up to date" stops meaning merely *caught up* and
/// starts meaning *caught up with nothing more coming*. A caught-up show that still
/// has unaired episodes then falls through to the arms below on its own, so it
/// lands in "To watch" while it's active and still drops to "Haven't watched in a
/// while" after [`STALE_DAYS`] with no watching and no new episode — deliberately
/// NOT pinned to "To watch", which would make the category grow without bound.
///
/// The two fallbacks are load-bearing and easy to lose:
/// * "started" also accepts `nb_episodes_seen`, so an imported show with a counter
///   but no watch rows is never called "Haven't started";
/// * "caught up" also accepts `seen >= total`, for shows whose episodes carry no
///   mirrored air date and therefore have no "latest aired" to have seen.
pub fn state_case(tracking: &str, keep_upcoming: bool) -> String {
    // Splicing a Rust bool, not a bind: it's a literal `true`/`false`, and the
    // expression is folded away by the planner when the preference is off.
    let up_to_date = if keep_upcoming {
        format!("({CAUGHT_UP_EXPR} AND NOT {HAS_UPCOMING_EXPR})")
    } else {
        CAUGHT_UP_EXPR.to_string()
    };
    format!(
        "CASE \
           WHEN {tracking}.archived OR {tracking}.status = 'stopped' THEN 'stopped' \
           WHEN {tracking}.status = 'for_later' THEN 'for_later' \
           WHEN lw.last_watched IS NULL AND COALESCE(seen.seen_episodes, 0) = 0 \
                AND COALESCE({tracking}.nb_episodes_seen, 0) = 0 THEN 'not_started' \
           WHEN {up_to_date} THEN 'up_to_date' \
           WHEN lw.last_watched >= now() - interval '{STALE_DAYS} days' \
                OR ep.max_aired >= current_date - {STALE_DAYS} THEN 'watching' \
           ELSE 'stale' \
         END"
    )
}

/// A movie's equivalent bucket, over an `app.user_movie` alias.
///
/// Movies have no episodes, so only three of the six buckets can apply. Mapping
/// them onto the same names is what lets one saved section span both kinds — a
/// duplicated "Watch later" covers watch-listed movies and for-later series at
/// once.
pub fn movie_state_case(alias: &str) -> String {
    format!(
        "CASE \
           WHEN {alias}.watched THEN 'up_to_date' \
           WHEN {alias}.watchlist THEN 'for_later' \
           ELSE 'not_started' \
         END"
    )
}

/// Is this a bucket we know how to filter on?
pub fn is_valid(state: &str) -> bool {
    STATES.contains(&state)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_state_is_produced_by_the_case_expression() {
        // The filter's vocabulary and the classification must agree: a value the
        // CASE never returns would be a filter that silently matches nothing.
        // Both settings of the preference, since it rewrites one of the arms.
        for keep in [false, true] {
            let case = state_case("lib", keep);
            for state in STATES {
                assert!(case.contains(&format!("'{state}'")), "{state} missing from the CASE (keep={keep})");
            }
        }
    }

    #[test]
    fn the_preference_narrows_up_to_date_and_touches_nothing_else() {
        let off = state_case("lib", false);
        let on = state_case("lib", true);
        assert_ne!(off, on);

        // Only "up to date" changes: it gains "and nothing more is coming".
        assert!(on.contains(HAS_UPCOMING_EXPR), "the preference must consult the upcoming flag");
        assert!(!off.contains(HAS_UPCOMING_EXPR), "and must not when it is off");

        // The stale rule is untouched, so a show still drops out of "To watch"
        // after a month of no watching and no new episode. Pinning the whole arm
        // because relaxing it is the tempting way to implement this — and it would
        // grow "To watch" without bound.
        let stale_arm = format!(
            "WHEN lw.last_watched >= now() - interval '{STALE_DAYS} days' \
             OR ep.max_aired >= current_date - {STALE_DAYS} THEN 'watching'"
        );
        for case in [&off, &on] {
            assert!(case.contains(&stale_arm), "the watching/stale rule must be identical either way");
        }

        // And the earlier arms keep their precedence: an archived or watch-later
        // show is never pulled into "To watch" by this.
        for case in [&off, &on] {
            let up_to_date = case.find("'up_to_date'").unwrap();
            assert!(case.find("'stopped'").unwrap() < up_to_date);
            assert!(case.find("'for_later'").unwrap() < up_to_date);
            assert!(case.find("'not_started'").unwrap() < up_to_date);
        }
    }

    #[test]
    fn movie_states_are_a_subset_of_the_series_ones() {
        let movie_case = movie_state_case("um");
        for state in ["up_to_date", "for_later", "not_started"] {
            assert!(movie_case.contains(&format!("'{state}'")), "{state} missing");
            assert!(is_valid(state));
        }
    }

    #[test]
    fn the_ctes_reference_the_user_bind_everywhere_it_matters() {
        let ctes = watch_state_ctes("$7");
        // Every watch_event scan must be scoped to the user; a missing bind would
        // silently mix other people's history into the aggregate.
        assert_eq!(ctes.matches("$7").count(), 3, "lw, seen and caught each scope by user");
        assert!(!ctes.contains("$1"), "the bind position is the caller's to choose");
    }
}
