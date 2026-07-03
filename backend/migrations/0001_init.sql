-- TV Show Tracker — initial schema.
-- Two schemas:
--   catalog.*  mirrored TheTVDB metadata (read-through cache; PKs = TheTVDB ids; refreshable)
--   app.*      our users and their tracking/social data (source of truth; irreplaceable)

CREATE SCHEMA IF NOT EXISTS catalog;
CREATE SCHEMA IF NOT EXISTS app;

-- ============================================================
-- catalog: mirror of TheTVDB. Every row keeps `raw` (full API
-- payload we didn't map), `last_updated` (TheTVDB's lastUpdated,
-- drives /updates reconciliation), and `last_synced_at` (when WE
-- last fetched it, drives read-through TTL).
-- ============================================================

CREATE TABLE catalog.series (
  id              BIGINT PRIMARY KEY,          -- TheTVDB series id
  name            TEXT,
  slug            TEXT,
  overview        TEXT,
  status          TEXT,
  year            INT,
  runtime         INT,
  image_url       TEXT,
  original_country  TEXT,
  original_language TEXT,
  score           DOUBLE PRECISION,
  last_updated    TIMESTAMPTZ,                 -- from TheTVDB lastUpdated
  raw             JSONB,
  last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted         BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX series_slug_idx ON catalog.series (slug);

CREATE TABLE catalog.movie (
  id              BIGINT PRIMARY KEY,
  name            TEXT,
  slug            TEXT,
  overview        TEXT,
  status          TEXT,
  year            INT,
  runtime         INT,
  image_url       TEXT,
  score           DOUBLE PRECISION,
  last_updated    TIMESTAMPTZ,
  raw             JSONB,
  last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted         BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX movie_slug_idx ON catalog.movie (slug);

CREATE TABLE catalog.season (
  id              BIGINT PRIMARY KEY,
  series_id       BIGINT REFERENCES catalog.series(id) ON DELETE CASCADE,
  number          INT,
  type            TEXT,                         -- season-type (official/dvd/absolute...)
  name            TEXT,
  image_url       TEXT,
  year            INT,
  last_updated    TIMESTAMPTZ,
  raw             JSONB,
  last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted         BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX season_series_idx ON catalog.season (series_id);

CREATE TABLE catalog.episode (
  id              BIGINT PRIMARY KEY,           -- TheTVDB episode id
  series_id       BIGINT REFERENCES catalog.series(id) ON DELETE CASCADE,
  season_number   INT,
  number          INT,
  absolute_number INT,
  name            TEXT,
  overview        TEXT,
  aired           DATE,
  runtime         INT,
  image_url       TEXT,
  is_movie        BOOLEAN,
  finale_type     TEXT,
  last_updated    TIMESTAMPTZ,
  raw             JSONB,
  last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted         BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX episode_series_idx ON catalog.episode (series_id);
CREATE INDEX episode_series_season_idx ON catalog.episode (series_id, season_number, number);

CREATE TABLE catalog.artwork (
  id              BIGINT PRIMARY KEY,
  series_id       BIGINT REFERENCES catalog.series(id) ON DELETE CASCADE,
  movie_id        BIGINT REFERENCES catalog.movie(id) ON DELETE CASCADE,
  season_id       BIGINT REFERENCES catalog.season(id) ON DELETE CASCADE,
  episode_id      BIGINT REFERENCES catalog.episode(id) ON DELETE CASCADE,
  type            INT,                          -- resolve via /artwork/types
  language        TEXT,
  image_url       TEXT,                         -- TheTVDB CDN URL (origin)
  thumbnail_url   TEXT,
  width           INT,
  height          INT,
  score           DOUBLE PRECISION,
  s3_key          TEXT,                         -- set once mirrored into Garage (nullable)
  last_synced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw             JSONB
);
CREATE INDEX artwork_series_idx ON catalog.artwork (series_id);
CREATE INDEX artwork_movie_idx  ON catalog.artwork (movie_id);

CREATE TABLE catalog.genre (
  id    BIGINT PRIMARY KEY,
  name  TEXT NOT NULL,
  slug  TEXT
);

CREATE TABLE catalog.series_genre (
  series_id  BIGINT REFERENCES catalog.series(id) ON DELETE CASCADE,
  genre_id   BIGINT REFERENCES catalog.genre(id) ON DELETE CASCADE,
  PRIMARY KEY (series_id, genre_id)
);

-- Sync bookkeeping for the future /updates worker (see docs/thetvdb-api.md §4).
CREATE TABLE catalog.sync_state (
  id            BOOLEAN PRIMARY KEY DEFAULT true CHECK (id),  -- single-row table
  last_sync_ts  BIGINT,                                       -- unix ts passed to /updates?since=
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- app: our users and their data (see docs/datamining.md §4).
-- ============================================================

CREATE TABLE app.users (
  id            BIGINT PRIMARY KEY,             -- may reuse imported TV Time id
  screen_name   TEXT NOT NULL,
  email         TEXT UNIQUE,
  password_hash TEXT,                            -- auth strategy TBD
  gender        TEXT,
  birthday      DATE,
  bio           TEXT,
  country_code  TEXT,
  avatar_url    TEXT,
  cover_url     TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app.user_follow (
  follower_id   BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  followee_id   BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);

CREATE TABLE app.user_show (
  user_id             BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  series_id           BIGINT NOT NULL,          -- TheTVDB id (catalog.series, populated read-through)
  is_followed         BOOLEAN NOT NULL DEFAULT false,
  is_favorited        BOOLEAN NOT NULL DEFAULT false,
  status              TEXT,                      -- NULL | 'for_later' | 'stopped' | 'archived'
  archived            BOOLEAN NOT NULL DEFAULT false,
  active              BOOLEAN NOT NULL DEFAULT true,
  diffusion           TEXT DEFAULT 'original',
  follow_source       TEXT,                      -- 'onboarding' | 'see-season' | ...
  notification_type   INT,
  notification_offset INT,                       -- minutes
  nb_episodes_seen    INT NOT NULL DEFAULT 0,
  last_seen_episode_id BIGINT,
  followed_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, series_id)
);
CREATE INDEX user_show_user_idx ON app.user_show (user_id);

CREATE TABLE app.watch_event (
  id            BIGSERIAL PRIMARY KEY,
  user_id       BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  entity_type   TEXT NOT NULL,                   -- 'episode' | 'movie'
  series_id     BIGINT,
  episode_id    BIGINT,
  movie_id      BIGINT,
  season_number INT,
  episode_number INT,
  runtime       INT,
  is_rewatch    BOOLEAN NOT NULL DEFAULT false,
  bulk_type     TEXT,                            -- '', 'season', 'fill-previous', ...
  source_uuid   TEXT UNIQUE,                     -- original tracking uuid → idempotent import
  watched_at    TIMESTAMPTZ NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX watch_event_user_idx ON app.watch_event (user_id, watched_at);
CREATE INDEX watch_event_episode_idx ON app.watch_event (user_id, episode_id);

CREATE TABLE app.episode_rewatch (
  user_id     BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  episode_id  BIGINT NOT NULL,
  count       INT NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, episode_id)
);

CREATE TABLE app.episode_rating (
  user_id     BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  episode_id  BIGINT NOT NULL,
  vote        SMALLINT NOT NULL,                 -- parsed from vote_key {ep}-{user}-{vote}
  uuid        UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, episode_id)
);

CREATE TABLE app.emotion (
  id    INT PRIMARY KEY,
  name  TEXT NOT NULL
);

CREATE TABLE app.show_emotion (
  user_id     BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  series_id   BIGINT NOT NULL,
  emotion_id  INT NOT NULL REFERENCES app.emotion(id),
  count       INT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, series_id, emotion_id)
);

CREATE TABLE app.list (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  s_key       TEXT,                              -- 'favorite-series', 'collection', ...
  name        TEXT NOT NULL,
  description TEXT,
  is_public   BOOLEAN NOT NULL DEFAULT false,
  ordering    INT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE app.list_item (
  list_id     BIGINT NOT NULL REFERENCES app.list(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL,                     -- 'series' | 'movie'
  entity_id   BIGINT NOT NULL,
  position    INT,
  PRIMARY KEY (list_id, entity_type, entity_id)
);
