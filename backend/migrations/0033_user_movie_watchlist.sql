-- "Watch later" for movies (the series equivalent is user_show.status='for_later').
-- A movie is in the library when watched OR favorited OR on the watchlist.
ALTER TABLE app.user_movie ADD COLUMN IF NOT EXISTS watchlist BOOLEAN NOT NULL DEFAULT false;
