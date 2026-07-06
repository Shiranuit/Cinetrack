-- Carry TV Time's plan-to-watch ("towatch") movies through the import: they were
-- previously dropped because the app had no movie watchlist. Now that app.user_movie
-- has a `watchlist` flag (0033), stage the intent here too so a towatch-only movie
-- resolves to a catalog title and lands in the library's "Watch later" section.
ALTER TABLE app.import_movie
  ADD COLUMN IF NOT EXISTS watchlist BOOLEAN NOT NULL DEFAULT false;
