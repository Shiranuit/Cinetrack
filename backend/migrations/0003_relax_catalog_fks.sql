-- The catalog is a read-through cache: entities are fetched independently, so a
-- child (episode/season/artwork) may be mirrored before its parent series/movie.
-- Drop FK enforcement (keep the columns + indexes for joins); the /updates worker
-- handles deletions in code rather than via ON DELETE CASCADE.
ALTER TABLE catalog.episode DROP CONSTRAINT IF EXISTS episode_series_id_fkey;
ALTER TABLE catalog.season  DROP CONSTRAINT IF EXISTS season_series_id_fkey;
ALTER TABLE catalog.artwork DROP CONSTRAINT IF EXISTS artwork_series_id_fkey;
ALTER TABLE catalog.artwork DROP CONSTRAINT IF EXISTS artwork_movie_id_fkey;
ALTER TABLE catalog.artwork DROP CONSTRAINT IF EXISTS artwork_season_id_fkey;
ALTER TABLE catalog.artwork DROP CONSTRAINT IF EXISTS artwork_episode_id_fkey;
