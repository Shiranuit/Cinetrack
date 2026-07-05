-- Add a "movies" showcase block to profiles so a user's tracked movies appear on
-- their profile alongside shows (previously movies only surfaced as a stat count).
-- New accounts get it by default; existing users have it appended so it shows up
-- for them too, kept last to preserve whatever order they already chose.
ALTER TABLE app.users
    ALTER COLUMN profile_blocks SET DEFAULT '{stats,favorites,shows,movies}';

UPDATE app.users
    SET profile_blocks = profile_blocks || ARRAY['movies']
    WHERE NOT ('movies' = ANY(profile_blocks));
