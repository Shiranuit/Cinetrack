#!/usr/bin/env bash
# Bootstrap a fresh single-node Garage: assign a storage layout, create the
# artwork bucket, create an S3 key, and grant access. Run once after the first
# `docker compose up -d garage`. Prints the S3 access/secret keys — paste them
# into your env file (S3_ACCESS_KEY / S3_SECRET_KEY), then start the backend.
#
# Targets whatever stack `docker compose` resolves. In PRODUCTION, point it at the
# prod file (docker compose reads COMPOSE_FILE natively) and paste into .env.production:
#   COMPOSE_FILE=production.docker-compose.yaml scripts/garage-init.sh
set -euo pipefail

SVC=garage
BUCKET="${S3_BUCKET:-artwork}"
g() { docker compose exec -T "$SVC" /garage "$@"; }

echo "==> Waiting for Garage to report a node id..."
NODE_ID=""
for _ in $(seq 1 30); do
  NODE_ID="$(g node id -q 2>/dev/null | cut -d@ -f1 || true)"
  [ -n "$NODE_ID" ] && break
  sleep 1
done
[ -n "$NODE_ID" ] || { echo "Garage node id not available; is the container up?" >&2; exit 1; }
echo "    node id: $NODE_ID"

echo "==> Assigning storage layout (single zone 'dc1', 1G capacity)..."
if ! g layout show | grep -q "$NODE_ID"; then
  g layout assign -z dc1 -c 1G "$NODE_ID"
  g layout apply --version 1
else
  echo "    layout already assigned, skipping"
fi

echo "==> Creating bucket '$BUCKET' (idempotent)..."
g bucket create "$BUCKET" 2>/dev/null || echo "    bucket exists"

echo "==> Creating S3 key 'backend'..."
KEY_OUT="$(g key create backend 2>/dev/null || g key info backend --show-secret)"
echo "$KEY_OUT"

echo "==> Granting key 'backend' read/write on '$BUCKET'..."
g bucket allow --read --write --owner "$BUCKET" --key backend

echo ""
echo "==> Done. Copy the Key ID and Secret key above into .env:"
echo "    S3_ACCESS_KEY=<Key ID>"
echo "    S3_SECRET_KEY=<Secret key>"
echo "Then: docker compose up -d --build backend"
