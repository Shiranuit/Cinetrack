# CLI & scripts

Cinetrack ships admin binaries (compiled into the backend image) and ops shell scripts.

## Backend binaries

Each binary lives in `backend/src/bin/` and reads the same configuration as the server. Run
them in development with `cargo run --bin <name>`, or in a running stack with
`docker compose exec backend <name>` (for tools that need the live server) /
`docker compose run --rm backend <name>` (for one-off tasks).

In production, prefix compose with the env file, for example:

```bash
DC="docker compose -f production.docker-compose.yaml --env-file .env.production"
$DC exec backend create_user you@example.com 'password' 'Name'
```

| Binary | Purpose | Example |
| --- | --- | --- |
| `backend` | The HTTP API server (default). Applies migrations on boot; optionally runs the sync/enrich workers. | `cargo run` |
| `create_user` | Create a user account (needed when public sign-up is off). Args: `<email> <password> [screen_name]`. | `$DC exec backend create_user a@b.com 'pw' 'Alice'` |
| `reset_password` | Reset a user's password (lockout recovery). Args: `<email> <new-password>`. | `$DC exec backend reset_password a@b.com 'newpw'` |
| `migrate` | Apply DB migrations without starting the server. Handy before seeding, or while the server is stopped. | `$DC run --rm backend migrate` |
| `sync` | Run one TheTVDB `/updates` sync pass and exit (cron-friendly). | `$DC run --rm backend sync` |
| `mirror` | Fill the local mirror and exit. In `MIRROR_SCOPE=full`, seed-crawls the whole catalog then drains the enrichment queue; in `on-demand`, just drains. | `$DC run --rm backend mirror` |
| `import` | Import a TV Time GDPR export zip. Args: `<path-to-zip> [target-user-id]`. Idempotent. | `$DC run --rm backend import /data/export.zip` |
| `backfill_facets` | One-off: re-derive filter facets (genres/tags/companies, season/episode counts) for mirrored series from stored raw data. No TheTVDB calls. | `$DC run --rm backend backfill_facets` |
| `backfill_unavailable` | One-off: flag library shows whose TheTVDB id now 404s as `unavailable`, so the UI hides dead cards. | `$DC run --rm backend backfill_unavailable` |

## Ops scripts (`scripts/`)

By default the data scripts target production
(`docker compose -f production.docker-compose.yaml --env-file .env.production`); override with
`DC=...`.

| Script | What it does |
| --- | --- |
| `garage-init.sh` | Bootstrap a fresh single-node Garage: create the layout, an `artwork` bucket, and an S3 access key, then print the keys to paste into your env. Run once. For prod: `COMPOSE_FILE=production.docker-compose.yaml ./scripts/garage-init.sh`. |
| `create-user.sh` | Convenience wrapper around the `create_user` binary. Usage: `scripts/create-user.sh <email> <password> [screen_name]`. |
| `db-dump.sh` | Full gzipped `pg_dump` backup (schema + all data). Usage: `scripts/db-dump.sh [output-file]`. |
| `db-seed.sh` | Load a `.sql` or `.sql.gz` into Postgres (stops on first error). Usage: `scripts/db-seed.sh <file>`. For users, use `create-user.sh` instead (passwords can't come from raw SQL). |
| `db-migrate.sh` | Apply migrations without starting the server (wraps `run --rm backend migrate`). |
| `firewall-cloudflare.sh` | Restrict the published 80/443 ports to Cloudflare's edge IPs via the `DOCKER-USER` iptables chain and an ipset. Run as root. Leaves SSH untouched. |
| `mail-dkim.sh` | Print the DKIM DNS TXT record from the running `mailer` container, plus suggested SPF/DMARC records. |
| `run-local.sh` | Dev helper: run a backend binary on the host while Postgres/Garage stay in Docker (rewrites compose hostnames to `localhost`). Usage: `scripts/run-local.sh` or `BIN=sync scripts/run-local.sh`. |
| `warm-cache.sh` | Dev helper: prime the read-through cache by fetching a list of series ids. Usage: `BASE_URL=http://localhost:8080 ./scripts/warm-cache.sh`. |

## systemd units (`deploy/`)

- `cloudflare-firewall.service` + `cloudflare-firewall.timer`: install these to refresh the
  Cloudflare-only firewall weekly (Cloudflare's IP ranges change over time). See
  [`deploy/README.md`](../deploy/README.md).
