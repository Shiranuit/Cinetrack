-- Per-entity translations, mirrored on demand from TheTVDB's
-- /{series,movies,episodes,seasons}/{id}/translations/{language} endpoints.

CREATE TABLE catalog.translation (
  entity_type    TEXT   NOT NULL,          -- 'series' | 'movie' | 'episode' | 'season'
  entity_id      BIGINT NOT NULL,
  language       TEXT   NOT NULL,          -- 3-letter code: eng, jpn, fra, ...
  name           TEXT,
  overview       TEXT,
  is_alias       BOOLEAN,
  is_primary     BOOLEAN,
  raw            JSONB,
  last_synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (entity_type, entity_id, language)
);
CREATE INDEX translation_entity_idx ON catalog.translation (entity_type, entity_id);

-- Original language, so we can label base records and skip redundant fetches.
ALTER TABLE catalog.movie ADD COLUMN IF NOT EXISTS original_language TEXT;
