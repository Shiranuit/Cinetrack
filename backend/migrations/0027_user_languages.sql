-- Preferred content languages, in priority order (used for translation ordering in
-- search/discover/library). Stored on the user so the choice syncs across devices,
-- like is_private / profile_blocks. Defaults to English.
ALTER TABLE app.users
    ADD COLUMN IF NOT EXISTS languages text[] NOT NULL DEFAULT '{eng}';
