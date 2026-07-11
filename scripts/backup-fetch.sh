#!/usr/bin/env bash
# List and download off-site Cinetrack backups from the Dedibackup FTP.
#
#   scripts/backup-fetch.sh list                 # what's on the FTP (marks last-good)
#   scripts/backup-fetch.sh get latest           # download the newest validated backup
#   scripts/backup-fetch.sh get 20260711-032001  # download a specific timestamp
#
# Downloads land in ./backup-download/ (override with OUT=...). Each `get` pulls the
# archive + its .meta sidecar and verifies the sha256 from the manifest.
#
# Why curl (not rclone): Dedibackup is PLAIN FTP, one session at a time, and the
# console password often contains URL-hostile characters. curl with `-u` is a single
# session and never URL-parses the credentials, so both problems go away. Run this on
# the production server (its IP is on the Dedibackup allow-list) unless you've added
# your current IP in the Dedibox console > Backup tab.
#
# Config: reads scripts/backup.env (same file backup.sh uses) for FTP_*.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f scripts/backup.env ]] || {
  echo "scripts/backup.env not found. Copy scripts/backup.env.example -> scripts/backup.env" >&2
  exit 1
}
set -a; source scripts/backup.env; set +a

FTP_DIR="${FTP_DIR:-cinetrack}"
FTP_PORT="${FTP_PORT:-21}"
FTP_TLS="${FTP_TLS:-off}"
OUT="${OUT:-backup-download}"
: "${FTP_HOST:?FTP_HOST missing from scripts/backup.env}"
: "${FTP_USER:?FTP_USER missing from scripts/backup.env}"
: "${FTP_PASS:?FTP_PASS missing from scripts/backup.env}"

BASE_URL="ftp://$FTP_HOST:$FTP_PORT/$FTP_DIR/"

# TLS: Dedibackup is 'off' (plain). Honour explicit/implicit for other providers.
tls_opt=()
case "$FTP_TLS" in
  explicit)    tls_opt=(--ssl-reqd) ;;
  implicit)    BASE_URL="ftps://$FTP_HOST:$FTP_PORT/$FTP_DIR/" ;;
  off|none|"") ;;
  *) echo "FTP_TLS must be explicit | implicit | off (got '$FTP_TLS')" >&2; exit 1 ;;
esac

# Single session, creds via -u so special chars are never URL-parsed.
CURL() { curl -fsS "${tls_opt[@]}" -u "$FTP_USER:$FTP_PASS" "$@"; }

# ts of the newest validated backup, from last-good.meta (empty if none).
last_good_ts() { CURL "${BASE_URL}last-good.meta" 2>/dev/null | sed -n 's/^ts=//p' | head -1; }

cmd_list() {
  local lg; lg="$(last_good_ts || true)"
  # One long listing -> pull "<size> <name>" for every cinetrack archive.
  local rows; rows="$(CURL "$BASE_URL" | awk '/cinetrack-[0-9]{8}-[0-9]{6}\.tar/ {print $5, $NF}' \
                        | grep -vE '\.meta$' | sort -k2)"
  [[ -n "$rows" ]] || { echo "No backups found in $BASE_URL"; return 0; }
  printf '%-20s %12s  %s\n' "TIMESTAMP" "SIZE" "FILE"
  while read -r size name; do
    local ts mark="" human
    ts="$(sed -E 's/^cinetrack-([0-9]{8}-[0-9]{6})\..*/\1/' <<<"$name")"
    [[ "$ts" == "$lg" ]] && mark="  <- last-good"
    human="$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size}B")"
    printf '%-20s %12s  %s%s\n' "$ts" "$human" "$name" "$mark"
  done <<<"$rows"
}

cmd_get() {
  local ts="${1:-}"
  [[ -n "$ts" ]] || { echo "usage: $0 get <timestamp|latest>" >&2; exit 1; }
  if [[ "$ts" == latest ]]; then
    ts="$(last_good_ts)"
    [[ -n "$ts" ]] || { echo "no last-good.meta on the FTP; pass an explicit timestamp (see 'list')" >&2; exit 1; }
    echo "latest validated backup: $ts"
  fi

  mkdir -p "$OUT"
  local meta="cinetrack-$ts.meta"
  echo "downloading $meta ..."
  CURL -o "$OUT/$meta" "${BASE_URL}${meta}"

  # The manifest tells us the archive suffix (.tar vs .tar.age) and its checksum.
  local enc sha archive
  enc="$(sed -n 's/^encrypted=//p' "$OUT/$meta")"
  sha="$(sed -n 's/^archive_sha256=//p' "$OUT/$meta")"
  archive="cinetrack-$ts.tar"; [[ "$enc" == age ]] && archive="$archive.age"

  echo "downloading $archive ..."
  CURL -o "$OUT/$archive" "${BASE_URL}${archive}"

  if [[ -n "$sha" ]]; then
    echo "verifying sha256 ..."
    sha256sum -c <<<"$sha  $OUT/$archive"
  else
    echo "WARN: no archive_sha256 in manifest; skipping integrity check" >&2
  fi

  echo
  echo "saved to $OUT/$archive"
  if [[ "$enc" == age ]]; then
    echo "encrypted (age). Decrypt on the machine holding the OFFLINE private key:"
    echo "    age -d -i key.txt \"$OUT/$archive\" > \"$OUT/cinetrack-$ts.tar\""
    echo "then: tar xf \"$OUT/cinetrack-$ts.tar\"   (see scripts/BACKUP.md for restore)"
  else
    echo "then: tar xf \"$OUT/$archive\"   (see scripts/BACKUP.md for restore)"
  fi
}

case "${1:-}" in
  list)      cmd_list ;;
  get)       shift; cmd_get "$@" ;;
  *) echo "usage: $0 {list | get <timestamp|latest>}" >&2; exit 1 ;;
esac
