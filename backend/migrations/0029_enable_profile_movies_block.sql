-- Ensure the "movies" showcase block is enabled on every existing profile.
--
-- 0028 already backfills this, but it may have been applied to a database before
-- that backfill (or the block was never appended for some rows). Migrations are
-- checksum-locked once applied, so we cannot re-run 0028; this standalone,
-- idempotent migration guarantees every profile has the block. Appends 'movies'
-- last so any custom block order the user chose is preserved, and touches only
-- rows that are actually missing it (so re-runs / already-correct rows are no-ops).
ALTER TABLE app.users
    ALTER COLUMN profile_blocks SET DEFAULT '{stats,favorites,shows,movies}';

UPDATE app.users
    SET profile_blocks = profile_blocks || ARRAY['movies']
    WHERE NOT ('movies' = ANY(profile_blocks));
