-- Tracks when a series' per-episode translations were last mirrored into
-- catalog.translation (entity_type='episode'). Lets the episode-translation
-- backfill resume across runs and enrichment skip already-mirrored series.
ALTER TABLE catalog.series
    ADD COLUMN IF NOT EXISTS episode_translations_synced_at timestamptz;
