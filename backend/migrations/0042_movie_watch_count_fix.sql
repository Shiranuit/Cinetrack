-- Reconcile movie tracking to the movie state model, repairing rows imported/created
-- before the model was enforced in code. The model:
--   * a movie is either WATCHED or in WATCH-LATER, never both;
--   * an un-watched movie carries no watch count;
--   * favoriting or rating a movie implies you watched it;
--   * a watched movie has a watch count >= 1 and at least one watch event (history).
--
-- The import/tracking code enforces all of this going forward; this migration brings
-- existing rows into line. Each step is idempotent, so the order only has to be
-- "mark-watched first, then normalize counts/flags, then backfill history".

-- 1. Favorite / rating imply watched (and, being watched, leave watch-later).
UPDATE app.user_movie
   SET watched = true,
       watched_count = GREATEST(watched_count, 1),
       watchlist = false,
       last_watched = COALESCE(last_watched, now()),
       updated_at = now()
 WHERE NOT watched AND (is_favorited OR rating IS NOT NULL);

-- 2. An un-watched movie carries no watch count. This is the main repair: the old
--    import forced watched_count = GREATEST(im.watched_count, 1), so plan-to-watch
--    (watch-later) movies got a phantom count of 1 — which pulled them out of
--    "Watch later" (filtered on watched_count = 0) and listed them under Movies as
--    if seen, and made the first real "watch" read "watched 2 times".
UPDATE app.user_movie
   SET watched_count = 0, updated_at = now()
 WHERE NOT watched AND watched_count <> 0;

-- 3. A watched movie is never in watch-later.
UPDATE app.user_movie
   SET watchlist = false, updated_at = now()
 WHERE watched AND watchlist;

-- 4. A watched movie has a count of at least 1.
UPDATE app.user_movie
   SET watched_count = 1, updated_at = now()
 WHERE watched AND watched_count < 1;

-- 5. A watched movie has at least one watch event (so it shows in history and the
--    count/history stay consistent). Deterministic-enough source_uuid via a random
--    uuid; only added when the movie has no movie event yet.
INSERT INTO app.watch_event (user_id, entity_type, movie_id, source_uuid, watched_at)
SELECT um.user_id, 'movie', um.movie_id,
       'movie-' || um.movie_id || '-' || gen_random_uuid(),
       COALESCE(um.last_watched, now())
  FROM app.user_movie um
 WHERE um.watched
   AND NOT EXISTS (
     SELECT 1 FROM app.watch_event w
      WHERE w.user_id = um.user_id AND w.movie_id = um.movie_id AND w.entity_type = 'movie');
