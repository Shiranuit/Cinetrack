#!/usr/bin/env bash
# Off-site backup of Cinetrack (Postgres + Garage artwork) to a Scaleway/Dedibox
# Dedibackup FTPS space. Designed to run nightly from cron on the server.
#
#   scripts/backup.sh              # normal run
#   DRY_RUN=1 scripts/backup.sh    # go through the motions, never upload/delete
#
# WHAT IT DOES, and why it is safe against a corrupted/empty database:
#
#   A new backup is fully built and VALIDATED before a single old backup can be
#   deleted. Validation has three layers (all must pass):
#     1. Integrity   - `pg_restore -l` must parse the dump and list >= MIN_TOC_ENTRIES.
#     2. Floors      - dump size and key row counts must clear absolute minimums.
#     3. Shrink guard - vs the last KNOWN-GOOD backup, the dump size and each row
#                       count must not have collapsed below SHRINK_RATIO (default 0.5).
#   A backup that fails is a SUSPECT: it is parked in suspect/ (off-box, capped) for
#   inspection, the last-good pointer is NOT moved, NOTHING is pruned, and the script
#   exits non-zero. So "DB wiped -> tiny dump" can never evict a good restore point.
#
#   Retention is SPACE-DRIVEN, not a fixed count (backup size is unknown/variable):
#   keep as many recent good backups as fit under QUOTA_BYTES; to make room for a new
#   VALIDATED backup, delete suspects first, then the oldest good ones, but NEVER below
#   MIN_KEEP. If it still will not fit at MIN_KEEP, the upload is aborted and an alert
#   fires (time to add storage) - existing good backups are left untouched.
#
# Config: copy scripts/backup.env.example -> scripts/backup.env (chmod 600) and fill in
# the FTP password + any tuning. S3/Garage keys are read from .env.production.
#
# Exit codes: 0 ok · 1 config/preflight · 2 build failed · 3 SUSPECT withheld
#             4 out of space (good backups kept) · 5 upload/verify failed
set -euo pipefail

# --- run from the repo root (this script lives in scripts/) ------------------
cd "$(dirname "$0")/.."

# --- config: defaults, then .env.production (S3), then backup.env (overrides) -
DC="${DC:-docker compose -f production.docker-compose.yaml --env-file .env.production}"
ENV_FILE="${ENV_FILE:-.env.production}"

# Retention / space (Dedibackup is 100 GB; leave headroom under the cap).
QUOTA_BYTES="${QUOTA_BYTES:-95000000000}"   # usable space to fill, in bytes (~95 GB)
MIN_KEEP="${MIN_KEEP:-3}"                    # never prune below this many good backups
MAX_KEEP="${MAX_KEEP:-0}"                    # 0 = unlimited (space is the only cap)
SUSPECT_KEEP="${SUSPECT_KEEP:-2}"           # keep at most this many parked suspects

# Anomaly thresholds.
SHRINK_RATIO="${SHRINK_RATIO:-0.5}"         # reject if a metric < ratio x last-good
ABS_MIN_PG_BYTES="${ABS_MIN_PG_BYTES:-1000000000}"   # a healthy dump is >= 1 GB
MIN_TOC_ENTRIES="${MIN_TOC_ENTRIES:-25}"
MIN_USERS="${MIN_USERS:-1}"
MIN_SERIES="${MIN_SERIES:-50000}"           # the mirrored catalog always has tens of thousands
GARAGE_MIN_FOR_RATIO="${GARAGE_MIN_FOR_RATIO:-1048576}"  # skip garage shrink check below 1 MB

# Where backups live remotely, local scratch, and tooling.
FTP_DIR="${FTP_DIR:-cinetrack}"
BASE="${BACKUP_BASE:-$HOME/.cinetrack-backup}"
RCLONE_IMAGE="${RCLONE_IMAGE:-rclone/rclone:latest}"
S3_BUCKET="${S3_BUCKET:-artwork}"
S3_REGION="${S3_REGION:-garage}"
S3_ENDPOINT_INTERNAL="${S3_ENDPOINT_INTERNAL:-http://garage:3900}"
ENCRYPT_CMD="${ENCRYPT_CMD:-}"   # e.g. 'age -r age1...' ; empty = store unencrypted
ALERT_CMD="${ALERT_CMD:-}"       # e.g. a curl to a webhook; receives the message on stdin

# Pull in FTP creds + any overrides (kept out of git; chmod 600).
# shellcheck disable=SC1090,SC1091
[[ -f scripts/backup.env ]] && { set -a; . scripts/backup.env; set +a; }
# S3 access/secret for Garage come from the production env file.
# shellcheck disable=SC1090,SC1091
[[ -f "$ENV_FILE" ]] && { set -a; . "$ENV_FILE"; set +a; }

# --- logging / alerting ------------------------------------------------------
ts_now() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { printf '%s  %s\n'  "$(ts_now)" "$*"; }
warn() { printf '%s  WARN: %s\n' "$(ts_now)" "$*" >&2; }
alert() {
  printf '%s  ALERT: %s\n' "$(ts_now)" "$*" >&2
  [[ -n "$ALERT_CMD" ]] && printf 'Cinetrack backup alert: %s\n' "$*" | eval "$ALERT_CMD" || true
}
die() { local code="$1"; shift; alert "$*"; exit "$code"; }

# --- preflight ---------------------------------------------------------------
: "${FTP_HOST:?set FTP_HOST in scripts/backup.env}"
: "${FTP_USER:?set FTP_USER in scripts/backup.env}"
: "${FTP_PASS:?set FTP_PASS in scripts/backup.env}"
: "${S3_ACCESS_KEY:?S3_ACCESS_KEY missing (from $ENV_FILE)}"
: "${S3_SECRET_KEY:?S3_SECRET_KEY missing (from $ENV_FILE)}"
command -v docker >/dev/null || die 1 "docker not found"
command -v tar >/dev/null || die 1 "tar not found"

umask 077
mkdir -p "$BASE"
MIRROR="$BASE/garage-mirror"; mkdir -p "$MIRROR"
STATE="$BASE/state"; mkdir -p "$STATE"
RCLONE_CONF="$STATE/rclone.conf"
LOCK="$STATE/backup.lock"

# Single-run lock so overlapping crons cannot race.
exec 9>"$LOCK"
flock -n 9 || die 1 "another backup run is already in progress"

# Per-run scratch, always cleaned.
WORK="$(mktemp -d "$BASE/work.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

TS="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="cinetrack-$TS.tar"
META="cinetrack-$TS.meta"

# The compose network Garage sits on (no published ports -> we join it).
NET="$($DC ps -q garage | head -n1 | xargs -r docker inspect \
        -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}')"
[[ -n "$NET" ]] || die 1 "could not find the running Garage container / its network"

# --- rclone config (garage S3 + dedibackup FTPS), 600, generated per run ------
FTP_PASS_OBSCURED="$(docker run --rm "$RCLONE_IMAGE" obscure "$FTP_PASS")"
cat > "$RCLONE_CONF" <<EOF
[garage]
type = s3
provider = Other
access_key_id = $S3_ACCESS_KEY
secret_access_key = $S3_SECRET_KEY
endpoint = $S3_ENDPOINT_INTERNAL
region = $S3_REGION
force_path_style = true

[ftp]
type = ftp
host = $FTP_HOST
user = $FTP_USER
pass = $FTP_PASS_OBSCURED
explicit_tls = true
EOF

# rclone, on the compose network, as this (non-root) user, config read-only.
RCLONE() {
  docker run --rm --network "$NET" --user "$(id -u):$(id -g)" -e HOME=/tmp \
    -v "$RCLONE_CONF":/cfg/rclone.conf:ro -v "$WORK":/work -v "$MIRROR":/mirror \
    "$RCLONE_IMAGE" --config /cfg/rclone.conf "$@"
}

# --- small helpers -----------------------------------------------------------
frac_lt() { awk -v a="$1" -v b="$2" -v r="$3" 'BEGIN{exit !(a < r*b)}'; }  # a < r*b ?
used_bytes() { RCLONE size --json "ftp:$FTP_DIR" 2>/dev/null | grep -oE '"bytes":[0-9]+' | head -1 | cut -d: -f2; }

count_rows() {
  local out
  out="$($DC exec -T postgres sh -c \
     "psql -tAqX -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -c 'SELECT count(*) FROM $1'" 2>/dev/null)" || return 1
  out="${out//[$'\r\n\t ']/}"
  [[ "$out" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$out"
}

list_good()    { RCLONE lsf --files-only "ftp:$FTP_DIR" 2>/dev/null        | grep -E '^cinetrack-[0-9]{8}-[0-9]{6}\.tar' | sed -E 's/^cinetrack-([0-9]{8}-[0-9]{6})\..*/\1/' | sort -u; }
list_suspect() { RCLONE lsf --files-only "ftp:$FTP_DIR/suspect" 2>/dev/null | grep -E '^cinetrack-[0-9]{8}-[0-9]{6}\.tar' | sed -E 's/^cinetrack-([0-9]{8}-[0-9]{6})\..*/\1/' | sort -u; }

delete_backup() {  # <timestamp> [remote-dir]
  local t="$1" dir="${2:-$FTP_DIR}"
  if [[ "${DRY_RUN:-0}" == 1 ]]; then log "DRY: would delete cinetrack-$t.* from $dir"; return 0; fi
  RCLONE delete --include "cinetrack-$t.*" "ftp:$dir" || warn "failed to delete $t from $dir"
}

prune_suspects() {
  local s; mapfile -t s < <(list_suspect)
  while (( ${#s[@]} > SUSPECT_KEEP )); do delete_backup "${s[0]}" "$FTP_DIR/suspect"; s=("${s[@]:1}"); done
}

# ============================================================================
# 1. Pull the last known-good metrics (baseline for the shrink guard).
# ============================================================================
declare -A LG
if RCLONE lsf --files-only "ftp:$FTP_DIR" 2>/dev/null | grep -qx "last-good.meta"; then
  RCLONE cat "ftp:$FTP_DIR/last-good.meta" > "$WORK/last-good.meta" 2>/dev/null || true
fi
[[ -s "$WORK/last-good.meta" ]] || cp -f "$STATE/last-good.meta" "$WORK/last-good.meta" 2>/dev/null || true
if [[ -s "$WORK/last-good.meta" ]]; then
  while IFS='=' read -r k v; do [[ -n "$k" ]] && LG["$k"]="$v"; done < "$WORK/last-good.meta"
  log "baseline last-good: pg=${LG[pg_bytes]:-?}B series=${LG[c_catalog_series]:-?} users=${LG[c_app_users]:-?}"
else
  log "no last-good baseline yet (first run) - only absolute floors will apply"
fi

# ============================================================================
# 2. Dump Postgres (custom format -> validatable + selective restore).
# ============================================================================
declare -A M
M[ts]="$TS"
log "dumping Postgres ..."
$DC exec -T postgres sh -c 'exec pg_dump -Fc --no-owner --no-privileges -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$WORK/pg.dump" \
  || die 2 "pg_dump failed"
M[pg_bytes]="$(stat -c%s "$WORK/pg.dump")"
# Integrity: the archive TOC must parse and be non-trivial.
M[toc_entries]="$($DC exec -T postgres pg_restore -l < "$WORK/pg.dump" 2>/dev/null | grep -cvE '^;|^[[:space:]]*$' || true)"
# Sentinel row counts (a wiped DB collapses these).
M[c_app_users]="$(count_rows app.users || echo 0)"
M[c_app_user_show]="$(count_rows app.user_show || echo 0)"
M[c_app_watch_event]="$(count_rows app.watch_event || echo 0)"
M[c_app_user_movie]="$(count_rows app.user_movie || echo 0)"
M[c_catalog_series]="$(count_rows catalog.series || echo 0)"
log "postgres: ${M[pg_bytes]}B, toc=${M[toc_entries]}, users=${M[c_app_users]}, series=${M[c_catalog_series]}, watches=${M[c_app_watch_event]}"

# ============================================================================
# 3. Mirror the Garage bucket (incremental) and measure it.
# ============================================================================
log "syncing Garage bucket '$S3_BUCKET' ..."
RCLONE sync "garage:$S3_BUCKET" /mirror --fast-list || die 2 "garage sync failed"
GS="$(RCLONE size --json "garage:$S3_BUCKET" 2>/dev/null || echo '{}')"
M[garage_objects]="$(printf '%s' "$GS" | grep -oE '"count":[0-9]+'  | head -1 | cut -d: -f2)"; M[garage_objects]="${M[garage_objects]:-0}"
M[garage_bytes]="$(printf '%s' "$GS"   | grep -oE '"bytes":[0-9]+'  | head -1 | cut -d: -f2)"; M[garage_bytes]="${M[garage_bytes]:-0}"
log "garage: ${M[garage_objects]} objects, ${M[garage_bytes]}B"

# ============================================================================
# 4. Build the archive (+ optional encryption) and fingerprint it.
# ============================================================================
log "building archive ..."
tar -cf "$WORK/$ARCHIVE" -C "$WORK" pg.dump -C "$BASE" garage-mirror
M[encrypted]=no
if [[ -n "$ENCRYPT_CMD" ]]; then
  log "encrypting archive ..."
  eval "$ENCRYPT_CMD" < "$WORK/$ARCHIVE" > "$WORK/$ARCHIVE.age" || die 2 "encryption failed"
  rm -f "$WORK/$ARCHIVE"; ARCHIVE="$ARCHIVE.age"; M[encrypted]=age
else
  warn "backups are stored UNENCRYPTED on the FTP (set ENCRYPT_CMD to change this)"
fi
M[archive_bytes]="$(stat -c%s "$WORK/$ARCHIVE")"
M[archive_sha256]="$(sha256sum "$WORK/$ARCHIVE" | cut -d' ' -f1)"

# Write the sidecar manifest (shell-parseable; no jq needed).
: > "$WORK/$META"
for k in ts pg_bytes toc_entries c_app_users c_app_user_show c_app_watch_event c_app_user_movie \
         c_catalog_series garage_objects garage_bytes archive_bytes archive_sha256 encrypted; do
  printf '%s=%s\n' "$k" "${M[$k]:-}" >> "$WORK/$META"
done

# ============================================================================
# 5. VALIDATE before anything old is touched. Fail -> park as SUSPECT.
# ============================================================================
REASONS=""
fail() { REASONS="${REASONS:+$REASONS; }$*"; }

(( M[pg_bytes]     >= ABS_MIN_PG_BYTES )) || fail "pg dump ${M[pg_bytes]}B below floor ${ABS_MIN_PG_BYTES}B"
(( M[toc_entries]  >= MIN_TOC_ENTRIES ))  || fail "pg_restore listed only ${M[toc_entries]} objects (dump unreadable/empty?)"
(( M[c_app_users]  >= MIN_USERS ))        || fail "users=${M[c_app_users]} below floor ${MIN_USERS}"
(( M[c_catalog_series] >= MIN_SERIES ))   || fail "catalog.series=${M[c_catalog_series]} below floor ${MIN_SERIES}"

if [[ -n "${LG[pg_bytes]:-}" ]]; then
  for key in pg_bytes c_app_users c_app_user_show c_app_watch_event c_app_user_movie c_catalog_series garage_bytes; do
    o="${LG[$key]:-0}"; n="${M[$key]:-0}"
    [[ "$o" =~ ^[0-9]+$ && "$o" -gt 0 ]] || continue
    [[ "$key" == garage_bytes && "$o" -lt "$GARAGE_MIN_FOR_RATIO" ]] && continue
    if frac_lt "$n" "$o" "$SHRINK_RATIO"; then fail "$key collapsed to $n from last-good $o (< ${SHRINK_RATIO}x)"; fi
  done
fi

if [[ -n "$REASONS" ]]; then
  warn "SUSPECT backup: $REASONS"
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    log "DRY: would park cinetrack-$TS in suspect/ and NOT prune anything"
  else
    RCLONE mkdir "ftp:$FTP_DIR/suspect" 2>/dev/null || true
    RCLONE copyto "/work/$ARCHIVE" "ftp:$FTP_DIR/suspect/$ARCHIVE" || warn "suspect archive upload failed"
    RCLONE copyto "/work/$META"    "ftp:$FTP_DIR/suspect/$META"    || warn "suspect manifest upload failed"
    prune_suspects
  fi
  die 3 "backup withheld as suspect (last-good pointer unchanged, nothing pruned): $REASONS"
fi
log "validation OK - treating this backup as GOOD"

# ============================================================================
# 6. Make room (suspects first, then oldest good, never below MIN_KEEP), upload.
# ============================================================================
RCLONE mkdir "ftp:$FTP_DIR" 2>/dev/null || true
need="${M[archive_bytes]}"
prune_suspects
used="$(used_bytes)"; used="${used:-0}"
mapfile -t goods < <(list_good)
i=0; n="${#goods[@]}"
while (( used + need > QUOTA_BYTES )) && (( n - i > MIN_KEEP )); do
  log "space: used=${used}B + new=${need}B over quota ${QUOTA_BYTES}B -> prune oldest good ${goods[i]}"
  delete_backup "${goods[i]}"; i=$((i+1))
  used="$(used_bytes)"; used="${used:-0}"
done
if (( used + need > QUOTA_BYTES )); then
  die 4 "not enough space for new backup even at MIN_KEEP=$MIN_KEEP (used=${used}B need=${need}B quota=${QUOTA_BYTES}B) - add storage; existing good backups were kept"
fi

if [[ "${DRY_RUN:-0}" == 1 ]]; then
  log "DRY: would upload $ARCHIVE (${need}B) + $META, then set last-good"
  log "DRY complete"; exit 0
fi

log "uploading $ARCHIVE (${need}B) ..."
RCLONE copyto "/work/$ARCHIVE" "ftp:$FTP_DIR/$ARCHIVE" || die 5 "archive upload failed"
RCLONE copyto "/work/$META"    "ftp:$FTP_DIR/$META"    || die 5 "manifest upload failed"

# Verify the uploaded size matches (rclone also checks on copy; belt and suspenders).
remote_size="$(RCLONE lsf --format sp "ftp:$FTP_DIR" 2>/dev/null | awk -F';' -v f="$ARCHIVE" '$2==f{print $1}')"
[[ "$remote_size" == "$need" ]] || die 5 "upload size mismatch (remote=${remote_size:-?} local=$need)"
log "upload verified"

# ============================================================================
# 7. Only now advance the last-good pointer, then optional MAX_KEEP trim.
# ============================================================================
cp -f "$WORK/$META" "$STATE/last-good.meta"
RCLONE copyto "/work/$META" "ftp:$FTP_DIR/last-good.meta" || warn "could not update remote last-good.meta"

if (( MAX_KEEP > 0 )); then
  mapfile -t goods < <(list_good)
  while (( ${#goods[@]} > MAX_KEEP )); do
    log "MAX_KEEP=$MAX_KEEP exceeded -> prune oldest good ${goods[0]}"
    delete_backup "${goods[0]}"; goods=("${goods[@]:1}")
  done
fi

log "backup $TS complete: archive=${need}B, kept $(list_good | wc -l) good backup(s), used=$(used_bytes)B / ${QUOTA_BYTES}B"
