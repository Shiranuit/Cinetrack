#!/usr/bin/env bash
# Warm the read-through cache with the ~360 series referenced in the GDPR export.
# Each GET /api/series/{id} triggers a TheTVDB fetch on miss and stores it locally,
# so afterwards the app serves those shows from Postgres. Run once the backend is up.
#
# Usage: BASE_URL=http://localhost:8080 ./scripts/warm-cache.sh
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
IDS_FILE="$(dirname "$0")/export-series-ids.txt"
SLEEP="${SLEEP:-0.2}"   # be gentle: TheTVDB rate limits are undocumented

total=$(wc -l < "$IDS_FILE" | tr -d ' ')
i=0; ok=0; fail=0
while read -r id; do
  [ -z "$id" ] && continue
  i=$((i+1))
  code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/api/series/$id")
  if [ "$code" = "200" ]; then ok=$((ok+1)); else fail=$((fail+1)); echo "  [$i/$total] id=$id -> HTTP $code"; fi
  printf '\r  progress: %d/%d (ok=%d fail=%d)   ' "$i" "$total" "$ok" "$fail"
  sleep "$SLEEP"
done < "$IDS_FILE"
echo ""
echo "==> Done. Cached $ok series ($fail failures) into catalog.series."
