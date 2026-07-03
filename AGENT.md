# AGENT.md — TV Show Tracker (TV Time replacement)

> Guidance for AI agents and developers working in this repository.
> Keep this file up to date as the project evolves.

## 1. What we're building

A self-hosted replacement for **TV Time** (the tracking app, shutting down). It lets users:

- Add TV content — **series, movies, anime** — and track it.
- **Track watched episodes** (per episode, with rewatch counts).
- Mark shows as **favorite**, **for later**, or **stopped/archived** ("stop watching").
- **Follow other users**, be followed, and share/view profiles.
- **Explore & discover** new shows and add them.
- Get **stats** (episodes watched per week/month, marathons, time spent).
- React to episodes with **emotions** and **rate** them.

Metadata (shows, episodes, artwork, people) comes from **TheTVDB** (v4 API). Per TheTVDB's own guidance, we **mirror their database locally** and keep it in sync via their `/updates` endpoint, to improve latency and resiliency and to reduce API load.

> **Architecture decision (confirmed):** TheTVDB's [v4-api README](https://github.com/thetvdb/v4-api) explicitly recommends three approaches — (1) maintain a full local DB copy, (2) run a caching proxy, (3) direct end-user access. We adopt **#1 (full mirror) as primary**, with **#2 (caching proxy) as an optional complementary layer**. See `docs/thetvdb-api.md` §0.
>
> **Auth model (confirmed):** we use **our own single project-level API key** (negotiated/commercial key, no per-user PIN). The key lives in env/`.env`, never in code.
>
> **Rollout (confirmed):** build the mirror as a **read-through cache** — on a cache miss the backend proxies the request to TheTVDB, stores the result in `catalog`, and serves locally thereafter. Start with just the **~360 shows referenced in the GDPR export** to prove the app end-to-end. Once proven, add a **full-seed script** (crawl all records) + the `/updates` sync worker. This defers the big crawl until the app demonstrably works.

## 2. Tech stack

| Layer | Choice | Notes |
|-------|--------|-------|
| Backend | **Rust** | See §7 for recommended crates (not yet committed). |
| Frontend | **Flutter** | Mobile (iOS/Android) + Web from one codebase. |
| Database | **PostgreSQL** | App data + mirrored TheTVDB metadata. |
| Object storage | **Garage** (S3-compatible) | Replaces MinIO — see `docs/storage.md`. |
| Orchestration | **docker-compose** | backend + postgres + garage (+ sync worker). |

**Do not introduce MinIO** — its OSS edition went into maintenance mode (Dec 2025) with a gutted admin UI. We use **Garage** (single Rust binary, zero deps, S3-compatible). Full rationale and alternatives in `docs/storage.md`.

## 3. Repository layout

```
/                    (NOT a git repo at root; `backend/` is its own repo)
├── AGENT.md         ← this file
├── README.md        quick-start / run instructions
├── docker-compose.yml   backend + postgres + garage
├── .env.example     config template (copy to .env)
├── docs/
│   ├── datamining.md    GDPR data model analysis → proposed schema
│   ├── thetvdb-api.md   TheTVDB v4 API reference + mirroring strategy
│   └── storage.md       S3-compatible storage decision (Garage)
├── garage/garage.toml   Garage single-node config
├── scripts/
│   ├── garage-init.sh       bootstrap Garage (layout + key + bucket)
│   ├── warm-cache.sh        prime the cache with the export's ~360 shows
│   └── export-series-ids.txt  series ids extracted from the GDPR export
├── backend/         Rust backend (axum + sqlx) — compiles; see §7
│   ├── migrations/0001_init.sql   catalog.* + app.* schema
│   └── src/                       layered modules:
│       ├── lib.rs                 library root (declares modules)
│       ├── main.rs                server bin (bootstrap + serve; optional sync worker)
│       ├── bin/import.rs          GDPR import CLI bin
│       ├── bin/sync.rs            /updates sync CLI bin
│       ├── sync/                  /updates incremental sync (domain): mod.rs
│       ├── config.rs error.rs state.rs   (infra; state has AppState::bootstrap)
│       ├── db/                    pool + migrations (infra)
│       ├── thetvdb/               API client (integration): mod.rs, client.rs
│       ├── storage/               Garage/S3 (integration): put/get artwork blobs
│       ├── auth/                  auth (domain): password.rs (Argon2id), token.rs (JWT), extractor.rs (AuthUser)
│       ├── catalog/               read-through mirror (domain):
│       │     mod.rs, models.rs, translation.rs, series.rs, movie.rs, episode.rs, season.rs, artwork.rs
│       ├── tracking/              user↔show + watch history + social (domain): mod.rs
│       ├── import/                GDPR importer (domain): mod.rs, source.rs (zip/csv), gomap.rs
│       └── web/                   HTTP transport: mod.rs (router), query.rs,
│             handlers/{health,auth,series,movie,episode,season,artwork,shows,watch,users}.rs
├── frontend/        Flutter app (still default scaffold, lib/main.dart only)
└── gdpr-data/       17 CSVs from the author's real TV Time account (see §5)
```

**`frontend/`** is still a fresh Flutter scaffold. **`backend/`** has a working, tested
read-through mirror: config, Postgres pool + migrations, a TheTVDB JWT client, per-entity
`catalog` modules (series/movie/episode/season/artwork) with translation overlay, and the
`/api/*` endpoints. Builds with `cargo build`.

## 4. Current status & roadmap

**Done:**
- Datamining of GDPR export; research on TheTVDB API + S3 storage (`docs/`).
- `docker-compose.yml` (postgres + garage + backend) + `.env.example` + Garage config/bootstrap.
- Postgres schema `catalog.*` + `app.*` (`backend/migrations/0001_init.sql`).
- Rust backend: config, DB pool + migrations, TheTVDB JWT client, layered modules (see §3).
- **Read-through cache** for series, movies, episodes, seasons, artwork — each `catalog/<entity>.rs` with `get(state, id, lang)`; endpoints `/api/{series,movies,episodes,seasons}/{id}` and `/api/artwork/{id}`. **Verified live** against TheTVDB with the real API key.
- **Multi-language translations** (`catalog.translation`, migration 0002): `?lang=eng` (default), `?lang=<code>` for any language, `?lang=original` for TheTVDB's base record. `GET /api/series/{id}/translations` lists available languages. Translations are read-through/cached per (entity, language).
- **Artwork mirroring into Garage** (S3 via `rust-s3`, `storage/mod.rs`): `GET /api/artwork/{id}/image` lazily downloads the blob from TheTVDB's CDN → stores in Garage → records `catalog.artwork.s3_key`, then serves from Garage thereafter. **Verified live** (243KB JPEG mirrored + served from Garage). Storage is optional — disabled cleanly when no S3 creds.
- `scripts/warm-cache.sh` + `export-series-ids.txt` to seed the export's ~360 shows.
- **GDPR import pipeline** (`backend/src/import/`, `cargo run --bin import -- <export.zip>`): reads the export zip, loads `app.*` (user with a fresh internal id deduped by original TV Time id via `external_tvtime_id`; consolidated `user_show`; `watch_event`; rewatches; ratings; favorites from the Go-map `objects` blob), prefetches referenced series into the catalog. **Idempotent + verified live** (1 user, 364 shows, 10,972 watch events; re-run = identical). Backend refactored to `lib.rs` + `main.rs`/`bin/import.rs` sharing `AppState::bootstrap`.
- **Auth** (email/password): **Argon2id** hashing (OWASP params) + **JWT** sessions (`JWT_SECRET`). `AuthUser` extractor gates protected routes. Endpoints: `POST /api/auth/register`, `POST /api/auth/login`, `GET /api/me`. **Verified live.**
- **Tracking API** (`tracking/`, auth-gated, **verified live**): `GET /api/shows` (joined w/ catalog); follow/favorite via `POST|DELETE /api/shows/{id}/{follow,favorite}`; `PUT /api/shows/{id}/status`; mark seen via `POST|DELETE /api/episodes/{id}/watch` (records `watch_event`, auto-detects rewatch, recomputes `nb_episodes_seen`/`last_seen_episode_id`); follow users via `POST|DELETE /api/users/{id}/follow`.
- **Browse endpoints:** `GET /api/search?q=&type=` (passthrough to TheTVDB `/search`), `GET /api/series/{id}/episodes?season_type=&lang=` (read-through, all pages, cached; `episodes_synced_at` TTL), `GET /api/series/{id}/seasons` (from the mirrored series record — seasons upserted when the series is fetched). **Verified live.**
- **Note:** emotions removed (migration 0005, not useful). Season *names* still come in original language (embedded, un-translated) — a follow-up if needed.

- **Flutter app "Cinetrack"** (`frontend/`, **redesigned** — builds + analyzes clean + smoke-verified): a real **design system** in `lib/design/` (tokens, `AppColors` ThemeExtension, `AppTheme` light/dark) with a "midnight-cinema" aesthetic (amber-gold accent; Bricolage Grotesque + DM Sans via google_fonts). Reusable widgets in `lib/widgets/`. Screens: adaptive nav shell (bottom bar Series/Movies/Search + rail on wide; profile avatar → menu), Series **library rails** (watching/stale/not-started/stopped), Search, Profile (stats + favorites + theme + language chips), show detail (blurred-poster hero, season-grouped collapsible episodes, **rewatch ×N**), login (show/hide password + OWASP checklist). Dark default + light toggle. API base via `--dart-define=API_BASE`. Model parsing uses Dart 3 **map patterns**. `tool/smoke.dart` drives the real client vs the backend.
- Backend gained `GET /api/shows/{id}` (single relationship) + `GET /api/shows/{id}/seen` (seen episode ids) for the app.

- **`/updates` sync worker** (`backend/src/sync/`, `cargo run --bin sync`, or in-server via `SYNC_INTERVAL_SECS`): polls TheTVDB `/updates` since `catalog.sync_state.last_sync_ts`, and **only for entities already in our mirror** re-fetches (refresh) or soft-deletes them; advances the checkpoint. First run just sets a baseline. Loops types series/movies/episodes/seasons (artwork excluded — lazy), with a page cap. **Verified live** (refreshed 10 changed entities, skipped 751 not-ours; stub series refreshed to its real name). Note: the kind is in `entityType` (`recordType` is often `""`).

**Next (suggested order):**
1. Richer app: profile/social screens, stats, per-season translated names, offline caching.
2. **Full-seed script** (crawl all records) for a complete mirror beyond the read-through set.
3. Deployment: build the backend Docker image into the compose stack; serve the Flutter web build; schedule `sync` (or set `SYNC_INTERVAL_SECS`).

Possible follow-ups for the mirror: episode/season **listing** per series (paginated), **search** (`/search`), and bulk-loading translations via `?meta=translations` on the extended endpoints to cut round-trips.

## 5. The GDPR data (`gdpr-data/`)

17 CSVs exported from **one real user** (`user_id = 43527855`, screen name "Shiranuit"). This is the ground truth for what data TV Time stored and therefore what we must model and be able to import. **Full column-by-column analysis and the proposed relational schema are in `docs/datamining.md`.** Highlights:

- Shows are keyed by **TheTVDB IDs** (`tv_show_id`, `episode_id`) — this is why the mirror uses the same IDs as primary keys.
- Watch history is large (~11k rows in `tracking-prod-records-v2.csv`) and event-shaped; the CSVs contain embedded Go-map (`map[...]`) blobs from a DynamoDB export — parse carefully.
- Show relationship to a user is multi-dimensional: followed / favorited / for-later / archived / stopped, plus per-show emotion counts, ratings, rewatches, and addiction scores.

## 6. TheTVDB integration (mirror + sync)

Full reference in `docs/thetvdb-api.md`. Key facts:

- **Base URL:** `https://api4.thetvdb.com/v4`; docs at `https://thetvdb.github.io/v4-api/`.
- **Auth:** `POST /login` with `apikey` (+ optional per-user `pin`) → JWT valid **1 month**. **No refresh endpoint** — re-login before expiry.
- **Licensing:** commercial license tiered by revenue (free under $50k/yr, attribution required); mirroring/proxying is **explicitly permitted and recommended**. Attribution with a link to TheTVDB.com must be shown to end users.
- **Mirroring pattern (sanctioned):** initial crawl of entity endpoints → then poll **`GET /updates?since=<unix_ts>`** on a schedule, re-fetch changed records, delete removed ones (handle `mergeToId`). **No bulk DB dump exists** — you must crawl + sync.
- **Rate limits: undocumented.** Do not hard-code an RPS; be conservative and cache aggressively.
- **Artwork:** the API returns fully-qualified CDN URLs (`https://artworks.thetvdb.com/...`). Store the URL as returned; download into Garage on demand for resiliency (don't assume legacy `/banners/...` path conventions — those are v1–v3).

## 7. Conventions & guidance for agents

- **Secrets:** TheTVDB API key, DB creds, S3 keys go in env vars / `.env` (git-ignored), never committed. Reference them via config.
- **Separate concerns in the DB:** mirrored TheTVDB data (`catalog.*`, refreshable, keyed by TheTVDB IDs) vs. user data (`app.*`). Never mix — the catalog can be rebuilt from TheTVDB; user data cannot.
- **Rust:** prefer `axum` (web), `sqlx` (compile-time-checked queries + migrations) or `sea-orm`, `tokio`, `reqwest` (TheTVDB client), `aws-sdk-s3` or `rust-s3` (Garage). These are recommendations — confirm before adding.
- **When modeling from the GDPR data,** consult `docs/datamining.md` rather than re-parsing CSVs from scratch.
- **Verify before asserting:** the research in `docs/` was gathered 2026-07-02; TheTVDB API details are pinned to spec v4.7.10. Re-check the live swagger if something looks off.
- Keep `docs/` authoritative and this file as the map. Update both when decisions change.

### 7a. Frontend (Flutter) rules — READ BEFORE EDITING `frontend/`

These are hard rules. Violating the first one has caused a recurring runtime crash
("setState() callback argument returned a Future"), so it's non-negotiable.

- **NEVER put an assignment in an arrow-body `setState`.** An arrow `() => x = y`
  *returns* the assigned value; if `y` is a `Future` (very common: `x = api.foo()`,
  `_future = _fetch()`), `setState` throws at runtime — and `flutter analyze` does
  **not** catch it. Always use a **block body** for assignments:
  ```dart
  // ❌ WRONG — returns the Future, crashes at runtime
  setState(() => _future = api.library());
  // ✅ RIGHT
  final f = api.library();
  setState(() { _future = f; });
  ```
  Rule of thumb: `setState(() => …)` is only OK for a non-assigning call
  (`setState(() => _expanded = !_expanded)` is fine because a `bool` isn't a Future,
  but prefer block bodies for *any* assignment to be safe).
- **Do async work BEFORE `setState`, never inside it.** Compute/await first, then
  synchronously assign inside `setState`.
- **Design system, not raw values.** Use `lib/design/` tokens (`Insets`, `Radii`,
  `Motion`, `Breakpoints`), `context.colors` / `context.scheme` / `context.text`, and
  the shared widgets in `lib/widgets/` (`Poster`, `ShowCard`, `PosterRail`,
  `SectionHeader`, `NetImage`, `WatchControl`, …). Don't hardcode colors, paddings, or
  `Image.network` — use `NetImage` (cached + retry + placeholder) for all remote images.
- **JSON parsing** uses Dart 3 map patterns in `api/models.dart` (validate at the
  boundary). Keep new models consistent with that style.
- **`mounted` guard** every `setState`/`context` use that follows an `await`.
- Run `flutter analyze` after edits; it must be clean before you call it done.

### 7b. Backend testing — structure & how to run

Two layers, both expected to grow with new code:

- **Unit tests** live in a dedicated **`src/<module>/tests.rs`** file per module
  directory, declared in that module's `mod.rs` as `#[cfg(test)] mod tests;` (NOT
  inline `#[cfg(test)] mod tests { … }` blocks). They cover pure logic only — no DB,
  no network: JSON coercion (`catalog::{as_i32,as_i64,image_url}`, `search::map_result`),
  query parsing (`web::query::{LangQuery,LangsQuery,csv_ids}`), CSV/gomap parsers
  (`import::{source,gomap}`), password policy + JWT (`auth`). Run with `cargo test --lib`.
  To test a private helper from `tests.rs`, bump it to `pub(crate)`.
- **Integration tests** live in **`backend/tests/`** (Rust's convention — each file is
  its own crate linking the lib). `tests/common/mod.rs` is the shared harness:
  `state()` builds an `AppState` against **`TEST_DATABASE_URL`** (runs migrations),
  `guard()` serializes tests (one shared DB), `clean()` truncates, plus fixture
  builders (`insert_user/insert_series/genres_raw/follow/insert_episode/watch…`). Tests
  call the real domain queries (`tracking::library`, `catalog::discover::search_db`,
  `tracking::calendar`, `tracking::delete_account`) and assert. **They SKIP when
  `TEST_DATABASE_URL` is unset** so `cargo test` stays green without a DB.
  - The throwaway DB is its own compose service, **`postgres-test`** (host port
    **5433**, tmpfs storage, `test` profile so it never starts with a plain
    `docker compose up`). Bring it up, then just run the tests — the harness loads
    `TEST_DATABASE_URL` from `.env.local` (it also checks `../.env.local` so
    `cargo test` works from `backend/`):
    ```sh
    docker compose up -d postgres-test
    cargo test --manifest-path backend/Cargo.toml   # or: cd backend && cargo test
    ```
    Never point `TEST_DATABASE_URL` at the dev DB — the harness truncates everything.

## 8. Decisions

**Confirmed:**
- TheTVDB access = **our own single project-level API key** (no per-user PIN).
- Mirror = **read-through cache**, seeded lazily; start with the **~360 shows from the GDPR export**; add a **full-seed script + `/updates` worker** only once the app is proven.
- Keep the `raw` JSONB on catalog rows (add mapped columns later without re-crawling); revisit trimming it on `episode`/`artwork` before the full seed.
- **Auth = email/password**, hashed with **Argon2id** (OWASP params), **JWT** sessions.
- **Artwork** mirrored into Garage lazily via read-through (`/api/artwork/{id}/image`).

**Still open:**
- Federation / how social profiles are shared across instances (for now, single-instance follows).
