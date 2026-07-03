-- Some imported shows reference TheTVDB ids that were later merged/deleted, so
-- the read-through fetch 404s and they can never resolve. Flag them during
-- import/prefetch so the library can hide them instead of showing dead cards.
ALTER TABLE app.user_show ADD COLUMN IF NOT EXISTS unavailable BOOLEAN NOT NULL DEFAULT false;
