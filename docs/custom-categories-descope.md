# Descope plan: keep the Library layout + filters, park custom categories

Working note, not documentation. Delete when done.

## Why

Custom user-created categories are being parked. The motivating complaint — shows
leaving "À regarder" once you're caught up until a new episode airs — is one
behaviour, and a filter-builder is a large surface to solve it. What ships is the
Library **layout** (hide/show/reorder) and the **new filter options**; what gets
parked is user-authored saved categories.

Consequence worth knowing: **the batch endpoint has zero callers once custom
categories go.** It existed only to fetch custom rails. Removing it also removes
the pool-starvation regression, all-or-nothing batch failure, the `MAX_BATCH`
cross-language coupling, and the "stored user queries replayed forever" hazard.

## State at the time of writing

- Branch `flexible-categories`, HEAD `1111786`, **9 modified uncommitted files**.
- Verified green: backend 61 unit + 30 integration, `cargo clippy --all-targets`
  exit 0; frontend 85 tests, `flutter analyze lib/ test/` clean.
- Four review rounds done (SQL correctness, API/security, client contract,
  mutation-testing). Findings either fixed or listed under "Still open" below.

### Environment gotchas

- Dev DB: `tvshow` on `localhost:5432` (container `tv-show-postgres-1`).
  User `f79e672d-ba83-49bc-b55e-0d86a7d1c064` has 372 tracked shows / 11.5k watches.
- Backend tests need a scratch DB:
  ```
  docker exec -i tv-show-postgres-1 sh -c 'psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE tvshow_st"'
  TEST_DATABASE_URL='postgres://tvshow:change-me-dev-only@localhost:5432/tvshow_st' cargo test
  ```
  Drop it afterwards. **Tests pass vacuously when `TEST_DATABASE_URL` is unset**:
  `tests/common/mod.rs` returns `None` and every test does
  `let Some(state) = … else { return }`, so they *run and report success*.
  Counting tests does NOT detect this — you get "30 passed" either way. To check
  you're really hitting a database, run one DB-dependent test and confirm it fails
  against an empty/missing schema, e.g.
  `cargo test --test integration -- --exact library_rails_and_state_filter_agree`
  against a database with no migrations applied.
- `docker compose up postgres-test` fails: port 5433 is held by an unrelated
  project's container.
- Run the backend: `./scripts/run-local.sh` (redirect to a log file; it's chatty
  because `DB_PROFILE=1`).

## Step 1 — preserve (do this first, nothing else before it)

The keep/discard line runs *inside* files, so this cannot be split by commit.
Preserve the whole state, then delete forward.

```
git add -A
git commit -m "Custom categories: full state before descope"
git branch custom-categories
```

`custom-categories` is the reference for reintroducing later. After the deletion,
`git diff flexible-categories custom-categories` is a readable diff of exactly the
parked surface.

## Step 2 — delete forward on `flexible-categories`

### Backend — remove

- `web/handlers/discover.rs`: `library_filter_batch`, `BatchEntry`, `BatchRequest`,
  `BatchResult`, `MAX_BATCH`, `RAIL_LIMIT`, `SNAPSHOT_TABLE`, `SNAPSHOT_MIN_RAILS`,
  `should_build_snapshot` + its unit test.
- `web/mod.rs`: the `/api/library/filter/batch` route, and its entry in
  `is_expensive`.
- `catalog/discover.rs`: `WatchState`, `search_db_on` (fold back into `search_db`),
  `Filters::needs_watch_state`, `Filters::with_progress`, `Filters::exclude_anime`
  and its predicate, the `is_anime` select, the progress columns select.
  **Leave `max_limit` alone.** (An earlier draft said to revert it to a flat
  `clamp(1, 200)` "because the 2000 ceiling existed only for uncapped rails" —
  that rationale is wrong. It is gated on `library_user.is_some()`, so it also
  covers `/api/library/filter` and `/api/users/{id}/filter`. Reverting would cap
  the Library's flat search page at 200 rows, a visible regression on a 372-show
  library. If you do want `main`'s ceiling back, do it as a separate, deliberate
  change.)
- `catalog/mod.rs`: `SearchResult::{total_episodes, seen_episodes, is_anime}`.
- `web/handlers/discover.rs` `DiscoverQuery`: `with_progress`, `exclude_anime`.
- `tracking/state.rs`: `SNAPSHOT_COLUMNS`, `watch_state_snapshot_sql`,
  `watch_state_ctes_from_snapshot`, and the `the_snapshot_carries_every_column…`
  unit test.

### Backend — KEEP (do not over-delete)

- `tracking/state.rs`: everything else — `STATES`, `STALE_DAYS`,
  `watch_state_ctes`, `watch_state_joins`, `CAUGHT_UP_EXPR`, `REMAINING_EXPR`,
  `PROGRESS_EXPR`, `HAS_UPCOMING_EXPR`, `state_case`, `movie_state_case`,
  `is_valid`.
- The `tracking::library` refactor (bucket comes from SQL). This is what stops the
  rails and the filter drifting apart.
- **All** watch-history facets, the `state` facet and the new sorts in `search_db` —
  they're still used by the Library's own filter sheet.
- `clamp_days`, `MAX_DAYS`, `MAX_EPISODES`, the NaN guards on `progress_*` and
  `score_min`. The fail-closed `states` handling (unknown value matches nothing).
- The two library-scoping fixes: movies via `user_movie`, series via
  `show_membership_sql`. These are the differential-verified behaviour changes.
- The `overview` removal (~⅔ of every search payload; no client ever parsed it).
- `tracking/sections.rs` entirely — table, caps, validation. The table stays and
  will hold built-in rows only. Keep `parse_filter_map` and the save-time gate in
  `web/handlers/users.rs`: the `filters` column still exists, so the door stays
  guarded.
- Migration `0044_library_sections.sql` unchanged.

### Frontend — remove

- `widgets/library_customize_sheet.dart`: `LibraryCategoryEditor`,
  `_duplicateCustom`, `_editCustom`, the "New category" button, the copy/delete
  row buttons. **Keep** reorder, the enable/disable switches, auto-save, and
  `_resetLayout`.
- `widgets/library_categories.dart`: `sectionQueryKinds`, `sectionQueryFilters`,
  `mergeSectionResults`, `mergedSectionFilters`, `sectionBatchKey`.
  **Keep** `builtinCats`, `sectionLabel`.
- `screens/library_screen.dart`: `_customItems`, `_loadCustomSections`,
  `_customTypeVisible`, `_kindSelected`, `_resultCard`, the custom branch in the
  section loop, and the refetch in `_adoptSections`.
- `api/api_client.dart`: `librarySectionsItems`.
- `api/models.dart`: `LibrarySection::{kinds, filters}` (keep `id`, `builtin`,
  `enabled`, and the defaults); `SearchResult::{isAnime, totalEpisodes,
  seenEpisodes, progress}`.
- l10n (all 9 locales): `addCategory`, `editCategory`, `categoryName`,
  `deleteCategory`, `duplicateCategory`, `categoryCopy`.

### Frontend — KEEP

- `api/filters.dart` **entirely** — every facet is still used by the Library filter
  sheet, and the half-open nullable bounds are the fix for the 1000-episode ceiling.
- `widgets/filter_sheet.dart` **entirely** — `_MinMaxSection`, the collapsible
  min/max sections, the tri-state chips, the sort tooltips, the library-only facet
  group. Discover gains the improved controls; the watch-history facets stay gated
  behind `showFavorites` (library scope).
- l10n: `customizeLibrary`, `resetLayout`, `resetLayoutConfirm`, `libNoSections`,
  `libSectionsHiddenByType`, `filterMin`/`filterMax`, all `filter*` facet labels,
  all `sort*` labels and `sortHelp*` strings, `yes`/`no`, `libraryStatus`.

### Tests — delete

`backend/tests/integration.rs`: `the_batch_handler_matches_per_section_queries_and_leaves_no_snapshot`,
`a_shared_snapshot_returns_what_per_query_ctes_return`,
`the_snapshot_never_outlives_its_transaction`,
`movie_rails_do_not_trigger_the_snapshot`,
`library_filter_batch_matches_individual_queries`,
`search_rows_carry_progress_only_when_requested`,
`exclude_anime_applies_before_the_limit`,
`a_library_rail_is_not_capped_at_a_page` (its subject `RAIL_LIMIT` is going).

`frontend/test/library_sections_test.dart`: `_multiKindTests`, `_progressTests`,
`_cardCaptionTests`. `frontend/test/library_customize_sheet_test.dart`:
`_kindRoundTrip`, `_duplicateTests`.

### Tests — KEEP

`library_rails_and_state_filter_agree` (the anti-drift property),
`library_scope_matches_main_except_for_the_two_intended_fixes` (pins the two
intended behaviour changes vs `main`), `watch_history_facets_and_the_seen_recently_view`,
`watch_history_ranges_are_half_open`, `an_unknown_state_filter_fails_closed`,
`library_sections_round_trip_and_default`,
`library_filter_scopes_movies_by_movie_membership`,
`a_watch_recency_sort_alone_does_not_filter_by_state`,
`the_save_handler_rejects_a_filter_that_would_break_the_library`, and the clamping
half of `poison_filters_are_rejected_at_save_and_survivable_at_load`.
All `tracking/sections.rs` and `tracking/state.rs` unit tests except the snapshot
one. Frontend: the range/label tests, sort-help tests, auto-save tests, reset-layout
tests.

### Verify after

```
cargo clippy --all-targets                       # expect exit 0
TEST_DATABASE_URL=... cargo test                 # unit
TEST_DATABASE_URL=... cargo test --test integration
cd frontend && flutter analyze lib/ test/ && flutter test
```
Then restart the backend and load the Library in the app.

## Still open after the descope

These survive the descope and are NOT fixed by it:

1. **The original complaint is still unsolved.** Dropping custom categories means
   there's no persistent "shows I'm actively watching, including caught-up ones".
   Smallest fix: a preference on the built-in category — *keep caught-up shows in
   À regarder for N days*. Independent of everything above.
2. **Lost edit during an in-flight save** (`library_customize_sheet.dart`). The
   layout still auto-saves, so this race remains: the re-flush at the end of
   `_flush` sits after `if (!mounted) return`, and `dispose` declines when
   `_saving` is true. Reproduced by review.
3. **Empty-state honesty.** A failed `_loadSections` is silent, and there's no
   branch for "sections visible but nothing matched" — it falls to `libEmpty`
   ("Nothing here yet"), which is wrong for a library of hundreds.
4. **The caps have no client counterpart.** Enabling a 16th category flips the
   switch, then 400s with an error line the user has scrolled past; nothing
   reverts. Client should enforce 15 active up front.
5. **Pre-existing, untouched:** unescaped `ILIKE` metacharacters in `q` (a leading
   `%` defeats the trigram index catalog-wide), no `statement_timeout`, no
   `CatchPanicLayer`, tests pass vacuously without `TEST_DATABASE_URL`, and
   `/dev/shm` at the container default 64 MB can be exhausted by parallel query.
6. **Series-includes-anime in the flat filter view** — `_filterPage` with Series
   selected still returns anime. Pre-existing on `main`; `exclude_anime` could have
   fixed it but is being removed as unused.

---

# Execution details (added after an audit pass)

An agent was given only this file and asked whether it could execute it. Step 1 was
fine; Step 2 was an inventory, not a procedure. These are the gaps it found. Read
this section BEFORE starting Step 2 — several items override the lists above.

## D1. Keep `LibrarySection.filters` and `.title` on the Dart model

Only drop `LibrarySection.kinds`. Reasons, in order of severity:

1. **Existing rows.** The dev DB already has custom sections. If the client drops
   `filters`, `toJson` sends `filters: null` for them, and
   `tracking::sections::validate` rejects the shape `(None, Some(title), None)` —
   so **every layout save 400s, permanently**, for any user who ever made one.
2. Two KEEP tests assert on it: `library_customize_sheet_test.dart` `_autoSaveTests`
   (recorder, ~line 145) and `_resetLayoutTests` (~lines 302, 348, which asserts
   `custom.single.filters == {'type': 'anime'}`).

Keeping both fields means existing custom rows round-trip untouched: they still
appear in the customize sheet (via `sectionLabel`'s `isCustom` branch), can still be
reordered and hidden, and are simply never *rendered as rails* and never creatable.
That is the desired parked state, and it needs no data migration.

## D2. Three test references that break the build

Not in either list in Step 2; all three must be handled:

- `frontend/test/api_notify_test.dart` — calls `librarySectionsItems` at ~lines 40
  and 62. **Delete** those two tests (`the batched library filter does not fire the
  change signal`, `an empty batch does not reach the network at all`). Keep
  `a real write still fires it`, which is about `_send`'s notify semantics.
- `frontend/test/library_sections_test.dart` `_mergeTests()` (~line 127) — entirely
  about `mergedSectionFilters`. **Delete.**
- `library_sections_test.dart` inline `group('LibrarySection')` in `main()`
  (~lines 87–122) — asserts filter serialization. **Keep** if D1 is followed
  (it compiles unchanged); delete only the `kinds` assertions.

Unclassified and fine either way: `_watchHistoryFacetTests`, `_presetSyncTests`,
`group('AdvancedFilters round trip')`, and
`anime_rail_filter_map_round_trips_and_returns_rows` (integration.rs) — all compile
after the descope.

## D3. `_customTypeVisible` vs `libSectionsHiddenByType` — resolve to DELETE both

The lists contradict each other: `_customTypeVisible` is the only producer of
`hiddenByType`, which is the only user of `libSectionsHiddenByType` (a KEEP string).
With no custom rails, a section can no longer be hidden by the type toggles, so the
branch is unreachable. **Delete `_customTypeVisible`, the `hiddenByType` branch, and
`libSectionsHiddenByType` from all 9 locales.** Keep `libNoSections` and its
Customize button — "no categories enabled" is still reachable.

## D4. Deletion order (build stays green at each step)

The reverse of the presentation order. Run `cargo check --all-targets` (backend) or
`flutter analyze lib/ test/` (frontend) after each.

- (a) `library_screen.dart`: custom branch in the section loop, `_customItems`,
      `_loadCustomSections`, `_customTypeVisible`, `_kindSelected`, `_resultCard`
- (b) `library_categories.dart` helpers + the test groups in D2
- (c) `api_client.librarySectionsItems` + the two `api_notify_test.dart` tests
- (d) `models.dart`: `LibrarySection.kinds`, `SearchResult::{isAnime,
      totalEpisodes, seenEpisodes, progress}` + tests asserting on them
- (e) `web/mod.rs`: the route and the `is_expensive` entry
- (f) `handlers/discover.rs`: the batch surface + its `#[cfg(test)] mod tests`
      block (delete the whole block, not just the fn — otherwise `use super::*`
      is left unused)
- (g) `catalog/discover.rs`: `WatchState`, `search_db_on`, `needs_watch_state`,
      `with_progress`, `exclude_anime`, the `is_anime` and progress selects
- (h) `tracking/state.rs`: the three snapshot items

## D5. Folding `search_db_on` back into `search_db`

**Do NOT `git checkout 1111786 -- backend/src/catalog/discover.rs`.** That reverts
three things the KEEP list wants: the `overview` removal, the narrowed `lib` CTE
(`SELECT us.series_id` instead of four columns), and the library-scoping fixes.

Do it by hand:
- delete the `WatchState` enum and the `(WatchState::Snapshot { .. }, true)` match arm
- rename `search_db_on` back to
  `pub async fn search_db(state: &AppState, f: &Filters, langs: &[String]) -> AppResult<Vec<SearchResult>>`
- drop the `exec` parameter and the `E: sqlx::Executor` bound; `.fetch_all(exec)`
  becomes `.fetch_all(&state.db)`
- delete the thin `search_db` wrapper that currently delegates
- **keep** the narrowed `lib` CTE and the `overview` removal; the
  `COALESCE(...)::bigint` progress columns go with `with_progress`

## D6. `is_anime` exists in two structs

`catalog::SearchResult::is_anime` → **delete**.
`tracking::LibraryShow::is_anime` (`tracking/mod.rs:159`) → **keep** — it feeds the
Library's type toggles (`library_screen.dart`) and `user_library_screen.dart`.
A grep-driven deletion will hit both.

## D7. `poison_filters_…` — what "the clamping half" means

The test compiles unchanged after the descope; nothing in it references a removed
symbol. Delete only the multi-kind assertion (`type=series,movie`, ~line 1208).
Keep everything else, including the `parse_filter_map` rejection assertions — the
save-time gate stays.

## D8. l10n regeneration

Edit the 9 `frontend/lib/l10n/app_*.arb` files, then run `flutter gen-l10n` from
`frontend/`. The 10 generated `lib/l10n/app_localizations*.dart` files are committed,
so they must be regenerated, not hand-edited.

## D9. Pre-existing warning

`backend/tests/integration.rs` has an unused `Filters` import inside a test that is
being deleted — it resolves itself.
