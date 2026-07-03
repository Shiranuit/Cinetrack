-- Track when we last synced a series' full episode list (drives the episode-list
-- read-through TTL, separate from the series row's own last_synced_at).
ALTER TABLE catalog.series ADD COLUMN IF NOT EXISTS episodes_synced_at TIMESTAMPTZ;

-- Speeds up per-show progress recompute in the tracking API.
CREATE INDEX IF NOT EXISTS watch_event_user_series_idx ON app.watch_event (user_id, series_id);
