-- TV Time's own stats-summary row (key='tracking-stats' in the tracking export)
-- is the source of truth for movie count + total watch time. We store it per user
-- and prefer it over deriving from the (sparse, unit-inconsistent) watch rows.
-- Runtimes are stored in SECONDS, exactly as the export provides them.
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS stat_movies             INT;
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS stat_episode_watches    INT;
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS stat_series_runtime_secs BIGINT;
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS stat_movies_runtime_secs BIGINT;
