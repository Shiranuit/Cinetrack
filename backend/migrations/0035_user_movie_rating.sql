-- Let users rate movies on the same labeled 1..5 scale as shows
-- (Hate it / Dislike it / OK / Like it / Love it, rendered as thumbs).
-- Rating a movie implicitly tracks it, just like rating a show.
ALTER TABLE app.user_movie
  ADD COLUMN IF NOT EXISTS rating SMALLINT;

ALTER TABLE app.user_movie
  ADD CONSTRAINT user_movie_rating_range CHECK (rating IS NULL OR rating BETWEEN 1 AND 5);
