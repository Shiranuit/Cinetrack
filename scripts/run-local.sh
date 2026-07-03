#!/usr/bin/env bash
# Run a backend binary on the HOST while Postgres + Garage run in docker compose.
# Loads .env.local, but rewrites the compose service hostnames (postgres/garage)
# to localhost so host processes can reach the exposed ports.
#
#   scripts/run-local.sh                 # run the server (default)
#   BIN=sync   scripts/run-local.sh      # run one /updates sync pass
#   BIN=import scripts/run-local.sh /path/to/export.zip
set -euo pipefail
cd "$(dirname "$0")/.."

ENV_FILE="${ENV_FILE:-.env.local}"
[ -f "$ENV_FILE" ] || { echo "missing $ENV_FILE (copy from .env.example)" >&2; exit 1; }

# Load env vars from the file, then point the two host-specific URLs at localhost.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
export DATABASE_URL="$(printf '%s' "${DATABASE_URL:-}" | sed 's/@postgres:/@localhost:/')"
export S3_ENDPOINT="$(printf '%s' "${S3_ENDPOINT:-}" | sed 's#//garage:#//localhost:#')"

exec cargo run --manifest-path backend/Cargo.toml --bin "${BIN:-backend}" -- "$@"
