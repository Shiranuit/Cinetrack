#!/usr/bin/env bash
# Apply DB migrations WITHOUT starting the server — run it while the backend is
# offline (e.g. before seeding the catalog, so the sync worker doesn't race the load).
# Uses `run --rm` so it works even when the backend service is stopped; it still
# brings up postgres (a dependency) if needed.
#
#   $DC stop backend            # take the server offline
#   scripts/db-migrate.sh       # apply migrations
#   scripts/db-seed.sh catalog-backup.sql.gz
#   $DC start backend           # back online
#
# Override compose with DC=... .
set -euo pipefail

DC="${DC:-docker compose -f production.docker-compose.yaml --env-file .env.production}"
exec $DC run --rm backend migrate
