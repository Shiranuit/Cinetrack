# Cinetrack

Self-hosted replacement for **TV Time**: track series/movies/anime, mark episodes seen,
favorite / for-later / stop-watching, follow other users, discover shows, and get stats.
Metadata comes from **TheTVDB** (v4), mirrored locally as a read-through cache.

- **Backend:** Rust (axum + sqlx) · **Frontend:** Flutter (mobile + web, en/fr UI)
- **DB:** PostgreSQL · **Object storage:** Garage (S3-compatible) · **Orchestration:** docker-compose

See **[AGENT.md](AGENT.md)** for the full guide and **[docs/](docs/)** for the data model
(`datamining.md`), TheTVDB integration (`thetvdb-api.md`), the mirror/sync design
(`thetvdb-sync-redesign.md`), and storage decision (`storage.md`).

## Quick start (dev)

```bash
# 1. Configure — secrets go in `.env` (docker compose ONLY auto-loads a file named `.env`).
cp .env.example .env
# edit .env: set POSTGRES_PASSWORD + matching DATABASE_URL, your THETVDB_API_KEY, JWT_SECRET,
# and generate secrets:  openssl rand -hex 32   (GARAGE_RPC_SECRET, GARAGE_ADMIN_TOKEN)
# (If you keep secrets in `.env.local`, symlink it:  ln -sf .env.local .env )

# 2. Start datastores
docker compose up -d postgres garage

# 3. Bootstrap Garage (creates layout + S3 key + bucket; paste printed keys into .env)
./scripts/garage-init.sh

# 4. Start the backend (runs DB migrations on boot)
docker compose up -d --build backend

# 5. Smoke test
curl localhost:8080/health
curl localhost:8080/api/series/74796   # Bleach — fetched from TheTVDB on first hit, cached after

# 6. Warm the cache with the shows from the GDPR export (~360 series)
./scripts/warm-cache.sh
```

## Run the backend on the host (Postgres + Garage still in Docker)

Keep the datastores in compose (`docker compose up -d postgres garage`) but run the Rust
backend directly. The `.env.local` URLs use the compose service names (`postgres`, `garage`),
so they must be rewritten to `localhost` for host access — `scripts/run-local.sh` does that:

```bash
scripts/run-local.sh                        # server on :8080
BIN=sync   scripts/run-local.sh             # one /updates sync pass
BIN=mirror scripts/run-local.sh             # fill the mirror (crawl in full scope, then enrich)
BIN=import scripts/run-local.sh export.zip  # GDPR import
```

## Catalog & sync modes

How the local mirror behaves is controlled by a few env vars (all annotated in
`.env.example`; deep design in `docs/thetvdb-sync-redesign.md`).

**`CATALOG_MODE`** — global read-through policy for *every* catalog read + search:

| Mode | Behaviour |
|------|-----------|
| `hybrid` *(default)* | Local mirror first; on a miss/thin result fall back to TheTVDB and **cache** it (self-healing). Best for dev + resilient prod. |
| `mirror` | Local DB **only** — never calls TheTVDB (miss → 404). Zero outbound dependency; the production goal. Pair with the sync worker to stay fresh. |
| `proxy` | Pure read-through passthrough to TheTVDB (still caches what it fetches). |

Search follows suit: `proxy` = TheTVDB search, `mirror` = local pg_trgm alias-aware
search, `hybrid` = local first with remote top-up.

**`MIRROR_SCOPE`** — how *much* of TheTVDB to hold (independent of `CATALOG_MODE`):

| Scope | Behaviour |
|-------|-----------|
| `on-demand` *(default)* | Mirror only what's asked about; `/updates` reconciles those, doesn't add new. Grows with usage; small footprint. |
| `full` | Mirror the whole catalog: resumable seed crawl (`bin/mirror`) + `/updates` adds new entities. Large but finite initial fill. |

**Staying fresh** — two cooperating jobs:

- **`/updates` sync** scans TheTVDB's global change feed since our checkpoint and
  enqueues what changed (per-row dedup, deletes, `mergeToId` repointing). The feed
  is *global*, so run it **often** (small windows). Server: `SYNC_INTERVAL_SECS`;
  one-off: `cargo run --bin sync`.
- **Enrichment** drains the queue, turning stubs into full records
  (`/extended?meta=translations` + episodes → translated titles offline). It's
  **event-driven** (Low priority) — woken the instant anything is enqueued (a
  searched/browsed stub, or an `/updates` change) — with `ENRICH_INTERVAL_SECS` as
  a fallback heartbeat and `ENRICH_CONCURRENCY` the parallelism. Bulk fill:
  `cargo run --bin mirror`.

Outbound rate is one global pacer (`THETVDB_MAX_RPS`, default 35 — undocumented
upstream, tune empirically). Interactive requests are prioritised over background
mirror work. **Artwork** is served from TheTVDB's CDN (not stored); object storage
holds only user-uploaded avatars & covers.

**Typical setups:** dev → `hybrid` + `on-demand` (defaults). Fully-offline prod →
run `MIRROR_SCOPE=full` with `bin/mirror` to fill, keep `SYNC_INTERVAL_SECS` +
`ENRICH_INTERVAL_SECS` running, then flip `CATALOG_MODE=mirror`.

Manual equivalent:

```bash
cd /path/to/tv-show
export DATABASE_URL=$(grep '^DATABASE_URL=' .env.local | cut -d= -f2- | sed 's/@postgres:/@localhost:/')
export S3_ENDPOINT=http://localhost:3900     # only needed for artwork mirroring
cargo run --manifest-path backend/Cargo.toml --bin backend
```

Prerequisites: Rust toolchain + `docker compose up -d postgres garage` running.
