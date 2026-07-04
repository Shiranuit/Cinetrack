# Configuration

Cinetrack's backend is configured entirely through **environment variables** (loaded from
`.env` in dev, `--env-file .env.production` in prod). This page is the complete reference.

- Dev template: [`.env.example`](../.env.example)
- Prod template: [`.env.production.example`](../.env.production.example)

## Required variables

| Variable | Meaning |
| --- | --- |
| `DATABASE_URL` | PostgreSQL connection URL, e.g. `postgres://user:pass@host:5432/tvshow`. |
| `JWT_SECRET` | Secret for signing session tokens (HS256). **Must be ≥ 32 characters** or the server refuses to start. Generate: `openssl rand -hex 32`. |
| `THETVDB_API_KEY` | Your TheTVDB v4 API key. |

## Networking & URLs

| Variable | Default | Meaning |
| --- | --- | --- |
| `BACKEND_BIND_ADDR` | `0.0.0.0:8080` | Address:port the API binds to. |
| `PUBLIC_BASE_URL` | `http://localhost:8080` | Public API URL; used to build absolute avatar/cover URLs. |
| `WEB_BASE_URL` | `http://localhost:8080` | Public **web-app** URL; used to build links in emails (password reset, invites). Must point at the Flutter web app, **not** the API. |
| `THETVDB_BASE_URL` | `https://api4.thetvdb.com/v4` | TheTVDB API base. |
| `THETVDB_MAX_RPS` | `35` | Global outbound rate cap (requests/sec) to TheTVDB. Tune empirically. |

## Authentication & registration

| Variable | Default | Meaning |
| --- | --- | --- |
| `ALLOW_PUBLIC_REGISTRATION` | `false` | `false` = invite-only sign-up (users need an invite code). `true` = anyone can register. Accepts `1`/`true`/`yes`. The login screen hides the "create account" button when this is off. |
| `PASSWORD_PEPPER` | _(unset)_ | Optional server-side secret mixed into every Argon2 password hash, kept out of the DB. **Set once and never change it** (existing hashes won't verify). Generate: `openssl rand -hex 32`. |

## Client versioning & forced updates

The backend advertises its version through the public `GET /api/config` endpoint, so
the app can detect when it's out of date. Both values are normally injected by CI, not
set by hand.

| Variable | Default | Meaning |
| --- | --- | --- |
| `APP_VERSION` | `dev` | This build's release tag (e.g. `v0.2.4`). **Baked into the backend image at build time** from the git tag (the CI release workflow passes it as a Docker build-arg); you rarely set it manually. Returned as `version` from `/api/config`. The Flutter app compares it to its own baked version to show an optional "a new version is available" banner. |
| `MIN_APP_VERSION` | = `APP_VERSION` | The compatibility-reference version, returned as `min_version`. A **native** app is hard-blocked by a non-dismissible "Update required" screen **only when it's behind this across a breaking boundary** - a new **major**, or (while still in 0.x) a new **minor**. Patch bumps, and minor bumps once at 1.0+, are backward-compatible and only trigger the optional "a new version is available" banner. The web app self-updates on reload, so it's never blocked. **Defaults to the running version**, so a breaking release forces mobile to update while patch releases don't. Set it explicitly to raise the floor manually (e.g. if a patch turns out to break compatibility). |

Notes:

- Version comparison only applies between real release tags (`vX.Y.Z`). On a `dev`/untagged
  backend both values are `dev`, so nothing is ever forced - safe for local runs.
- Forced updates only affect clients that already ship the version-check feature (v0.2.3+);
  older installs don't know about `min_version` and won't self-block until updated once.
- The matching APK is published from the same tag as the backend, so when the floor rises the
  new APK is already available (the in-app updater downloads the latest release asset).

## Catalog & sync

Two independent knobs control how the local mirror of TheTVDB behaves.

### `CATALOG_MODE` - read-through policy (default `hybrid`)

Applies to **every** catalog read (series/movies/episodes/seasons/artwork) and search.

| Mode | Behaviour |
| --- | --- |
| `hybrid` _(default)_ | Serve from the local mirror first; on a miss/thin result, fall back to TheTVDB and **cache** it (self-healing). Search: local first, remote top-up. Best for dev and resilient prod. |
| `mirror` | Local DB **only** - never calls TheTVDB (a miss returns 404). Zero outbound dependency; the fully-offline production goal. Pair with the sync worker to stay fresh. Search: local `pg_trgm` only. |
| `proxy` | Pure read-through passthrough to TheTVDB (still caches what it fetches). Search: TheTVDB. |

### `MIRROR_SCOPE` - how much to hold (default `on-demand`)

| Scope | Behaviour |
| --- | --- |
| `on-demand` _(default)_ | Only mirror entities you actually request. `/updates` reconciles what you already hold but doesn't pull in brand-new titles. Small footprint, grows with use. |
| `full` | Mirror the whole catalog: a resumable seed crawl (`bin/mirror`) plus `/updates` adding new entities. Large but finite initial fill. |

### Background workers

| Variable | Default | Meaning |
| --- | --- | --- |
| `SYNC_INTERVAL_SECS` | _(unset = disabled)_ | If set, the server runs the `/updates` sync worker every N seconds. The `/updates` feed is global - run it **often** (small windows). One-off equivalent: `cargo run --bin sync`. |
| `ENRICH_INTERVAL_SECS` | _(unset = disabled)_ | If set, runs the enrichment worker (turns stubs into full records). It's **event-driven** (woken on every enqueue); this interval is only a fallback heartbeat. Bulk fill: `cargo run --bin mirror`. |
| `ENRICH_CONCURRENCY` | `8` | Concurrent in-flight enrichment fetches (the `THETVDB_MAX_RPS` pacer still caps total throughput). |

**Typical setups:** dev → `hybrid` + `on-demand` (defaults). Fully-offline prod → run
`MIRROR_SCOPE=full` with `bin/mirror` to fill, keep the sync + enrich workers running, then
flip `CATALOG_MODE=mirror`.

## Object storage (S3 / Garage)

Only used for **user-uploaded avatars and covers**. (Show artwork is served from TheTVDB's
CDN, not stored.) Storage is optional - disabled cleanly if unset.

| Variable | Default | Meaning |
| --- | --- | --- |
| `S3_ENDPOINT` | _(empty)_ | S3 endpoint, e.g. `http://garage:3900`. Empty = storage disabled. |
| `S3_REGION` | `garage` | S3 region. |
| `S3_BUCKET` | `artwork` | Bucket name. |
| `S3_ACCESS_KEY` | _(empty)_ | S3 access key (from `scripts/garage-init.sh`). |
| `S3_SECRET_KEY` | _(empty)_ | S3 secret key. |

> `GARAGE_RPC_SECRET` and `GARAGE_ADMIN_TOKEN` are consumed by the **Garage container**, not
> the backend - see the compose files.

## Email (SMTP)

Used for password-reset and invitation emails. **Disabled unless `SMTP_HOST` is set** - when
disabled, the links are logged instead (fine for local dev with Mailpit).

| Variable | Default | Meaning |
| --- | --- | --- |
| `SMTP_HOST` | _(unset = mail disabled)_ | SMTP server host. Its presence enables sending. |
| `SMTP_PORT` | `587` | SMTP port. |
| `SMTP_USER` | _(empty)_ | SMTP username (omit for an unauthenticated internal relay). |
| `SMTP_PASS` | _(empty)_ | SMTP password. |
| `SMTP_TLS` | `starttls` | `starttls` (external providers on 587) or `none` (plain - only for a trusted relay on a private network, e.g. Mailpit in dev or the internal Postfix in prod). |
| `MAIL_FROM` | `Cinetrack <no-reply@localhost>` | The From header. |

See **[deployment.md](deployment.md#email)** for the recommendation to use a transactional
email provider rather than self-hosting SMTP.

## Diagnostics & performance

| Variable | Default | Meaning |
| --- | --- | --- |
| `RUST_LOG` | `info` | Log filter (`tracing` env-filter syntax). `.env.example` suggests `info,backend=debug`. |
| `DB_MAX_CONNECTIONS` | `20` | Postgres connection-pool size (shared by the HTTP server and background workers). |
| `DB_PROFILE` | `false` | When on, logs SQL statements **slower than `DB_PROFILE_MIN_MS`** (at WARN, with the statement text + elapsed time) and `EXPLAIN (ANALYZE, BUFFERS)`s the expensive read queries when they cross the threshold. Faster queries stay silent. |
| `DB_PROFILE_MIN_MS` | `50` | Slow-statement threshold in ms for `DB_PROFILE`. Lower to see more (`1` ≈ everything), raise for only the worst. |
| `BACKEND_PROFILE` | `false` | Appends per-request timing + connection-pool occupancy to each request log line (`… (N ms) [pool size=.. idle=..]`) and raises app logs to debug. Useful to tell whether latency is in the DB vs app/serialization, and to spot pool saturation. |

> `DB_PROFILE` / `BACKEND_PROFILE` are development/diagnostic tools - leave them off in
> production. When `DB_PROFILE` is off, the database driver still warns on any statement
> slower than 1 second.

Truthy flags (`DB_PROFILE`, `BACKEND_PROFILE`) accept `1`, `true`, `yes`, or `on`.
