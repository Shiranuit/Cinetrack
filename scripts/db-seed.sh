#!/usr/bin/env bash
# Load a .sql (or .sql.gz) file into the production Postgres, which isn't exposed to
# the network. Pipes the file into psql INSIDE the postgres container (credentials
# come from the container's own env). Stops on the first error (ON_ERROR_STOP), so a
# bad statement aborts instead of half-applying.
#
#   scripts/db-seed.sh <file.sql|file.sql.gz>
#
# Works for catalog/seed data or restoring a pg_dump. (For USERS, use create-user.sh —
# password hashes can't be produced from raw SQL.) Override compose with DC=... .
#
# Loading a big catalog dump into a fresh DB: stop the backend first so its sync
# worker doesn't race the COPYs:  $DC stop backend  →  this script  →  $DC start backend
set -euo pipefail

DC="${DC:-docker compose -f production.docker-compose.yaml --env-file .env.production}"
PSQL='exec psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "usage: $0 <file.sql|file.sql.gz>" >&2
  exit 1
fi

echo "==> Loading $1 into Postgres..."
case "$1" in
  *.gz) gunzip -c "$1" | $DC exec -T postgres sh -c "$PSQL" ;;
  *)    $DC exec -T postgres sh -c "$PSQL" < "$1" ;;
esac
echo "==> Done."
