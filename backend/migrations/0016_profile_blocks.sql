-- Per-user profile layout: which showcase blocks appear and in what order.
-- Stored server-side so a user's chosen layout is honored when others view
-- their profile. 'shows' replaces the former client-only 'watching' block.
ALTER TABLE app.users
    ADD COLUMN profile_blocks text[] NOT NULL DEFAULT '{stats,favorites,shows}';
