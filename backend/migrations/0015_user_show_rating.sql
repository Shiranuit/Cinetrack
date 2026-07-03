-- User's personal rating for a show (1..10, NULL = unrated). Powers "rate a show",
-- library sort-by-your-rating, and a show's average rating across all users.
ALTER TABLE app.user_show ADD COLUMN IF NOT EXISTS rating SMALLINT;
CREATE INDEX IF NOT EXISTS user_show_rating_idx ON app.user_show (series_id) WHERE rating IS NOT NULL;
