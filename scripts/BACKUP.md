# Off-site backups (Postgres + Garage) to Dedibackup

`scripts/backup.sh` builds a full backup of the database and the Garage artwork
bucket and pushes it, over FTPS, to the Dedibox Dedibackup space. Scaleway does not
run backups for a Dedibox; this is the thing that does.

## What is backed up

- **Postgres**: `pg_dump -Fc` (custom format: compressed, and validatable) of the
  whole database (app + catalog).
- **Garage**: an incremental `rclone sync` of the `artwork` bucket, tarred into the
  archive. Garage artwork is largely re-fetchable from TheTVDB, so it is lower
  criticality than Postgres, but it is included for a complete restore.

Each run uploads one archive `cinetrack-<ts>.tar[.age]` plus a small manifest
`cinetrack-<ts>.meta`, and updates `last-good.meta`.

## Why a corrupt database cannot destroy your backups

The new backup is fully built and **validated before any old backup is deleted**.
Validation is three layers, all must pass:

1. **Integrity** - `pg_restore -l` must parse the dump and list >= `MIN_TOC_ENTRIES`.
2. **Floors** - dump size >= `ABS_MIN_PG_BYTES`, `app.users` >= `MIN_USERS`,
   `catalog.series` >= `MIN_SERIES`.
3. **Shrink guard** - versus the last known-good backup, the dump size and the key
   row counts must not fall below `SHRINK_RATIO` (default 0.5x).

A backup that fails any check is a **suspect**: it is parked in `suspect/` (capped by
`SUSPECT_KEEP`) for you to inspect, the `last-good` pointer is left untouched,
**nothing is pruned**, and the script exits non-zero. So "database wiped -> tiny dump"
can never rotate out a good restore point.

## Retention is space-driven

Backup size is unknown and variable, so retention is by space, not a fixed count:

- Keep as many recent good backups as fit under `QUOTA_BYTES` (default ~95 GB, under
  the 100 GB Dedibackup cap).
- To make room for a new **validated** backup: delete suspects first, then the oldest
  good backups, but **never below `MIN_KEEP`** (default 3).
- If it will not fit even at `MIN_KEEP`, the upload is aborted and an alert fires
  (time to add storage). Existing good backups are kept.

## Setup

1. In the Dedibox console (Backup tab) set an FTP password, and ideally enable the
   IP **Access list** for your server plus **auto-login**.
2. Configure the script:
   ```
   cp scripts/backup.env.example scripts/backup.env
   chmod 600 scripts/backup.env
   # edit: set FTP_PASS (and FTP_HOST/FTP_USER if they differ), tune retention
   ```
   S3/Garage keys are read from `.env.production` automatically.
3. Dry run (builds + validates, uploads/deletes nothing):
   ```
   DRY_RUN=1 scripts/backup.sh
   ```
4. First real run (establishes the `last-good` baseline):
   ```
   scripts/backup.sh
   ```

## Schedule (cron, as the deploy user)

```
# nightly at 03:20, log to a file
20 3 * * *  cd /path/to/tv-show && ./scripts/backup.sh >> "$HOME/cinetrack-backup.log" 2>&1
```

Exit codes for monitoring: `0` ok, `1` config/preflight, `2` build failed,
`3` suspect withheld, `4` out of space (good backups kept), `5` upload/verify failed.
Set `ALERT_CMD` in `backup.env` to get a push (webhook/mail) on any failure.

## Encryption (recommended)

Backups sit on a third-party FTP. Set `ENCRYPT_CMD` in `backup.env` to encrypt each
archive before upload with a public key (the server never holds the private key):

```
ENCRYPT_CMD='age -r age1yourpublickey...'
```

Keep the age private key OFFLINE; you need it only to restore.

## Restore

```
# 1. Pull the archive + manifest, verify integrity
rclone copy ftp:cinetrack/cinetrack-<ts>.tar   .     # (configure an rclone ftp remote)
sha256sum -c <<<"$(grep archive_sha256 cinetrack-<ts>.meta | cut -d= -f2)  cinetrack-<ts>.tar"

# 2. Decrypt if it ends in .age
#    age -d -i key.txt cinetrack-<ts>.tar.age > cinetrack-<ts>.tar

# 3. Unpack
tar xf cinetrack-<ts>.tar          # -> pg.dump  and  garage-mirror/

# 4. Restore Postgres (into the running container)
DC="docker compose -f production.docker-compose.yaml --env-file .env.production"
$DC exec -T postgres sh -c 'pg_restore --clean --if-exists --no-owner --no-privileges \
    -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < pg.dump

# 5. Restore Garage artwork (re-upload the objects)
#    Using an rclone garage remote pointed at the S3 endpoint:
rclone sync garage-mirror garage:artwork

# 6. Restart the backend so it picks everything up
$DC restart backend
```

## Tuning knobs (in backup.env)

`QUOTA_BYTES`, `MIN_KEEP`, `MAX_KEEP`, `SUSPECT_KEEP`, `SHRINK_RATIO`,
`ABS_MIN_PG_BYTES`, `MIN_TOC_ENTRIES`, `MIN_USERS`, `MIN_SERIES`. Defaults are in
`scripts/backup.sh`. If a legitimately large deletion trips the shrink guard, the run
is withheld as a suspect (by design) - review it, and if it is genuinely correct,
promote it by copying its `.meta` to `last-good.meta` on the FTP, or loosen
`SHRINK_RATIO` for that run.
