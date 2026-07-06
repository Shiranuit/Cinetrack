-- Show ratings move from a 1..10 star scale to a labeled 1..5 scale
-- (Hate it / Dislike it / OK / Like it / Love it, rendered as thumbs).
-- Convert every existing rating into the new scale: {1,2}->1, {3,4}->2, {5,6}->3,
-- {7,8}->4, {9,10}->5 (integer (rating+1)/2), then enforce the new range so a stray
-- out-of-range value can never be written again.
--
-- Note: app.episode_rating (per-episode votes imported from TV Time) is a separate
-- historical dataset and is intentionally left on its original scale.
UPDATE app.user_show SET rating = (rating + 1) / 2 WHERE rating IS NOT NULL;

ALTER TABLE app.user_show
  ADD CONSTRAINT user_show_rating_range CHECK (rating IS NULL OR rating BETWEEN 1 AND 5);
