#!/usr/bin/env bash
# Full logical backup of the Postgres database (schema + ALL data — app + catalog),
# gzipped. Runs pg_dump INSIDE the postgres container (version-matched; the DB isn't
# exposed to the network).
#
#   scripts/db-dump.sh [output-file]
#
# Default output: db-backup-<timestamp>.sql.gz in the current directory.
# Restore into a FRESH database with:  scripts/db-seed.sh <file.sql.gz>
# Override compose with DC=... .
set -euo pipefail

DC="${DC:-docker compose -f production.docker-compose.yaml --env-file .env.production}"
OUT="${1:-db-backup-$(date +%Y%m%d-%H%M%S).sql.gz}"

echo "==> Dumping full database to $OUT ..."
$DC exec -T postgres sh -c 'exec pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --no-privileges' | gzip -6 > "$OUT"
echo "==> Done: $(du -h "$OUT" | cut -f1)  ($OUT)"
