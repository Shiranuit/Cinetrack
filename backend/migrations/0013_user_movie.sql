-- Per-user movie tracking (the series equivalent is app.user_show). A movie is in
-- the library when watched and/or favorited. Watch history/rewatches also land in
-- app.watch_event (entity_type='movie'); this table is the fast library view.
CREATE TABLE app.user_movie (
  user_id       BIGINT NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  movie_id      BIGINT NOT NULL,          -- TheTVDB movie id (catalog.movie)
  is_favorited  BOOLEAN NOT NULL DEFAULT false,
  watched       BOOLEAN NOT NULL DEFAULT false,
  watched_count INT NOT NULL DEFAULT 0,
  last_watched  TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, movie_id)
);
CREATE INDEX user_movie_user_idx ON app.user_movie (user_id);
