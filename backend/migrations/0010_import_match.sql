-- Uncertain (fuzzy) recoveries of dead TheTVDB ids during import. Exact-name
-- matches are applied automatically; fuzzy matches (normalized / small edit
-- distance) are recorded here as PENDING suggestions for the user to confirm or
-- reject in the UI, so a wrong guess is never silently applied.
CREATE TABLE app.import_match (
  id                  BIGSERIAL PRIMARY KEY,
  user_id             BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  dead_series_id      BIGINT NOT NULL,          -- the id from the export that 404s
  import_name         TEXT   NOT NULL,          -- name as it appeared in the export
  suggested_series_id BIGINT NOT NULL,          -- live TheTVDB id we think it is
  suggested_name      TEXT,                     -- that series' resolved name
  distance            INT    NOT NULL,          -- edit distance (0 = normalized-exact)
  status              TEXT   NOT NULL DEFAULT 'pending', -- pending | confirmed | rejected
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, dead_series_id)
);
CREATE INDEX import_match_user_status_idx ON app.import_match (user_id, status);
