-- Staging for GDPR movie import. TV Time's export identifies movies only by an
-- internal uuid + title (no TheTVDB id like series carry), so we stage the raw
-- intent here and resolve each title to a catalog.movie id by name search during
-- the prefetch phase (inline for the CLI, background for in-app uploads). Keeping
-- the staged rows makes the import idempotent and lets us retry/inspect the ones
-- that don't match a catalog movie. Idempotent per (user, source_uuid).
-- Only an *exact* title match (name/translation/alias) is auto-imported; an
-- uncertain fuzzy match becomes a `suggested` row the user confirms/rejects in the
-- same review screen as dead-series recoveries (see app.import_match). `id` is a
-- surrogate key so a suggestion can be addressed by the confirm/reject API.
CREATE TABLE app.import_movie (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY UNIQUE,
  user_id            UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  source_uuid        TEXT NOT NULL,     -- TV Time movie uuid
  name               TEXT,              -- original title (often Japanese)
  search_name        TEXT,             -- romanized/English title used for the search
  year               INT,
  runtime_secs       INT,
  watched            BOOLEAN NOT NULL DEFAULT false,
  watched_count      INT NOT NULL DEFAULT 0,
  last_watched       TIMESTAMPTZ,
  followed_at        TIMESTAMPTZ,
  resolved_movie_id  BIGINT,            -- catalog.movie id once matched/confirmed
  suggested_movie_id BIGINT,           -- best-guess candidate for an uncertain match
  suggested_name     TEXT,
  distance           INT,              -- edit distance of the uncertain match
  status             TEXT NOT NULL DEFAULT 'pending',  -- pending|matched|suggested|unmatched|rejected
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, source_uuid)
);
CREATE INDEX import_movie_pending_idx ON app.import_movie (user_id) WHERE status = 'pending';
