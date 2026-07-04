# Architecture

A high-level tour of how Cinetrack is built. For exact configuration knobs see
[configuration.md](configuration.md).

## Overview

```
   Flutter app (web / Android / iOS)
              │  HTTPS
              ▼
   Caddy (TLS, reverse proxy)  ──────  serves the web bundle
              │
              ▼
   Rust API (axum)  ──►  PostgreSQL   (app data + mirrored catalog)
        │        └────►  Garage (S3)  (avatars & covers)
        │
        └──►  TheTVDB v4 API  (metadata source, mirrored locally)
```

The backend is the only component that talks to the database, object storage, and TheTVDB.
The frontend is a pure API client.

## The two data domains

The database is split into two schemas that must never be mixed:

- **`catalog.*`** - mirrored TheTVDB metadata (series, movies, episodes, seasons, artwork,
  translations, genres, tags, companies). Keyed by **TheTVDB integer ids**. This is a cache:
  it can be rebuilt from TheTVDB at any time.
- **`app.*`** - user data (accounts, watch history, ratings, favorites, follows, invitations).
  Keyed by app-generated **UUIDv7** ids. This is the source of truth and cannot be regenerated.

Keeping them separate means the catalog can be re-crawled or wiped without touching user data.

## The catalog mirror (read-through cache)

TheTVDB's own guidance recommends mirroring their database locally rather than proxying every
request. Cinetrack does exactly that, as a **read-through cache**:

1. A request for a series/movie/episode hits the local mirror first.
2. On a miss (or a stale record), the backend fetches it from TheTVDB, stores it in `catalog.*`,
   and serves it. Subsequent requests are served locally.

How aggressively this happens is governed by `CATALOG_MODE` (`hybrid` / `mirror` / `proxy`)
and how much is held by `MIRROR_SCOPE` (`on-demand` / `full`). See
[configuration.md](configuration.md#catalog--sync).

### Staying fresh: two cooperating workers

- **Sync (`/updates`)** polls TheTVDB's global change feed since a stored checkpoint and, for
  entities already in the mirror, re-fetches changed records and soft-deletes removed ones
  (handling merges). Because the feed is global, it's meant to run often with small windows.
- **Enrichment** turns lightweight "stubs" (an id + name, created when something is
  searched/browsed or reported changed) into full records, including episodes and translated
  titles. It's **event-driven**: woken the instant anything is enqueued, running at low
  priority so it yields to interactive requests.

A single global rate limiter (`THETVDB_MAX_RPS`) caps all outbound TheTVDB traffic, and
interactive reads are prioritized over background mirror work.

### Artwork

Show posters/artwork are served directly from TheTVDB's CDN (their fully-qualified URLs are
stored, not the images). Object storage holds only **user-uploaded** avatars and covers.

## Search

Search uses PostgreSQL's `pg_trgm` extension with GIN trigram indexes on the searchable text
and on translation names, so it's fuzzy (tolerant of punctuation and spelling drift) and
alias/translation aware. Queries run as a union of index-friendly branches rather than a
single cross-table scan, and require at least 3 characters (shorter queries have no usable
trigram). In `hybrid` mode, thin local results are topped up from TheTVDB and cached.

## Authentication & sessions

- Passwords are hashed with **Argon2id** (OWASP parameters), with an optional server-side
  **pepper** (`PASSWORD_PEPPER`) kept out of the database.
- Sessions use **JWT** (HS256) access tokens signed with `JWT_SECRET`, plus refresh tokens
  (an httpOnly cookie on web, secure storage on mobile).
- Every non-public route is gated by an auth extractor; there's a per-user read rate limit on
  the expensive endpoints.
- Sign-up is invite-only by default (`ALLOW_PUBLIC_REGISTRATION`), with an invitation system.

## Request lifecycle (backend)

```
request → log → CORS → auth gate (+ read rate limit) → security headers → body limit → handler
```

Handlers are thin: they parse/validate input and delegate to domain modules (`catalog`,
`tracking`, `auth`, `import`) which own the SQL. Database access is `sqlx` with migrations
embedded at build time and applied automatically on server boot.

## Backend module map

| Module | Responsibility |
| --- | --- |
| `web/` | HTTP transport: router, middleware, request handlers. |
| `catalog/` | The read-through mirror: per-entity fetch/store, translations, search, discover/filters. |
| `tracking/` | User to show relationships, watch history, ratings, the social graph, library/stats. |
| `auth/` | Password hashing, JWT tokens, the `AuthUser` extractor. |
| `import/` | The TV Time GDPR export importer. |
| `sync/` | The `/updates` incremental sync and seed crawl. |
| `thetvdb/` | The TheTVDB v4 API client (JWT login, typed calls). |
| `storage/` | Garage/S3 blob put/get for avatars and covers. |
| `db/`, `config.rs`, `state.rs`, `email/`, `profile.rs` | Infrastructure: pool + migrations, config, shared state, mail, profiling. |

## Frontend

The Flutter app is a single codebase for web, Android, and iOS. It has a design-system layer
(`lib/design/`: tokens, theme extensions), reusable widgets, and API models parsed with Dart 3
map patterns. The API base URL, release version, and repo (for the APK download link) are baked
in at build time via `--dart-define`. The UI is localized into 9 languages via Flutter's
`gen-l10n` (ARB files in `lib/l10n/`).

## Deployment shape

The reference deployment is a **single server** behind **Cloudflare**, with all services
(API, web, Postgres, Garage, mail) in one Docker Compose stack and no external managed
services. This is intentionally low-cost and self-contained rather than horizontally scalable.
See [deployment.md](deployment.md).
