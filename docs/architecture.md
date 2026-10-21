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

Discover and Library name searches run locally against base titles, translations and
language-tagged aliases, using word matching and PostgreSQL GIN trigram indexes. Discover uses
a union of indexed branches; Library checks only the owner's tracked titles. Translated
titles and aliases match the viewer's languages plus each show's original language.
Ordinary queries use the same word tokenizer as the baseline: lowercase letters/numbers,
with punctuation and whitespace separating terms. Each term is matched independently
within the same title variant, so `laid-off` and `laid off` produce identical searches,
and `laid mage` can find words separated in a title. Terms can appear in any order.
Migration 0049 adds accent folding through PostgreSQL's standard `unaccent` dictionary
and Unicode NFC normalization. Input is folded once before tokenization and frequency
checks; expression indexes store folded title text for the matching predicates. Thus
`malgré moi`, `malgre moi` and decomposed accent input use the same representation,
including ligatures such as `œ` → `oe`. Display names keep their original spelling.
Words from separate aliases or translations are never combined.

Migration 0050 adds title relevance for every nonblank text search. Indexed word/exact
predicates first retrieve matching name variants; SQL scores those variants and keeps
the best score per title before sorting and pagination. Normalized exact titles rank
first, followed by a combination of word boundaries, query coverage of the title, and
small phrase/prefix bonuses. Base names, eligible translations and aliases can all
provide the winning match. Popularity only breaks equal textual scores, followed by
id for stable paging. The selected browsing sort and direction apply when text is empty;
facet filters and library scope apply in both modes. Watch aggregates are not loaded
just because an inactive browsing sort needs them.

Text-search results include `relevance` and `search_popularity` for the client's mixed
series/movie grid. `RankedSearchPager` merges the independently sorted streams, filling
an exhausted stream before selecting the next result, then cuts global pages. It keeps
unconsumed rows rather than applying the same offset to both streams and concatenating
pages. A query/filter/type change creates a new pager and disposes the old grid, so
pending requests cannot overwrite new search results. The filter sheet explains title
ordering and retains the browsing sort for when the search is cleared.

Local validation on 2026-10-21 used 1,465,216 eligible name variants for 532,201 titles
(English/French plus original-language variants), two warmups and seven timed runs.
Adding relevance increased selective SQL lookups by roughly 0.1–0.9 ms; the broad
`love` query increased from 31 to 67 ms. All eight known-intent targets stayed in the
top ten, and the exact *Malgré moi* series moved from fourth to first. Exact-title films
can correctly precede longer series titles for ambiguous input such as `laid off`.
This is a small regression set, not a general relevance-quality guarantee.

A second check copied the actual catalog title tables (about 532,000 entities,
1,392,346 translations and 173,336 aliases) into a disposable migrated database and
called the backend search function, including viewer metadata and language joins.
Warm selective searches took 3–12 ms per kind, `the` exact lookup 13–18 ms, and `love`
62–76 ms. Two-character Japanese fragments (`進撃 巨人`) remain a retrieval limitation:
448–957 ms, comparable to the pre-ranking matcher, since these terms provide no
selective trigrams. Library checks with seven tracked series took 2–3 ms. These are
local warm-cache measurements without HTTP or concurrent-user load.

Migration 0048 aggregates all active series/movie titles, translations and aliases
once into `catalog.search_word_baseline`, an offline word-frequency baseline.
Counts are distinct titles per language and content type, so duplicate aliases do not
inflate frequency. Three-character word prefixes are included for typing; episode names
and deleted titles are excluded. Base titles and original-language variants also form an
always-searchable cohort. Only terms matching at least 5,000 titles and 2% of a cohort
are stored in Postgres. Each server startup only loads this small snapshot into memory.
On the local catalog (about 533,000 titles), the initial aggregation took about 45 seconds
and produced 43 common term/language/type entries. That cost applies once during the
migration, before the listener starts; ordinary restarts never rescan titles, including
when the saved snapshot is empty. After a major catalog import an administrator can
explicitly run `SELECT catalog.refresh_search_word_baseline();` and restart the backend
to load the refreshed snapshot. No automatic rebuild is scheduled. Migration 0049
refreshes the saved baseline once with accent folding, so accented common terms follow
the same guard as their unaccented equivalents. It also rebuilds the exact-title indexes
and replaces raw-name trigram indexes with folded-name indexes; this adds work to that
first migration, not subsequent startups. The pinned unaccent dictionary is treated as
fixed for indexing; changing its rules requires rebuilding the dependent indexes.

A single common term or a one/two-character query uses indexed,
normalized exact-title lookup in Discover; punctuation-only input returns no matches.
This preserves short titles such as *It* and
*Up* while avoiding a catalog-wide substring scan. Exact-title normalization folds case
and accents and replaces punctuation with spaces. Full title, translation and alias equality use
dedicated indexes from migration 0047. Library searches and multi-word queries use
ordinary word matching. Frequency is a selectivity estimate, not a guarantee
of substring-match counts; longer incomplete words and interior substrings are not
fully represented by the word/prefix baseline.

The `/api/discover` response remains a JSON array and includes `x-search-mode: exact`
or `full` (also exposed through CORS). Discover displays a prompt to add another word
when broad matching was restricted, alongside any exact title matches. Blank input
browses normally. No remote API calls or frequency aggregation occur in a search request.

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
