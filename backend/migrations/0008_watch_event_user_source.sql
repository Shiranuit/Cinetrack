-- source_uuid was globally UNIQUE, but it originates from a TV Time export and is
-- only unique WITHIN one user's history. Importing the same export into two
-- accounts (or a test + the real account) made the second import collide and
-- silently drop every watch event. Scope idempotency to the user instead.
ALTER TABLE app.watch_event DROP CONSTRAINT IF EXISTS watch_event_source_uuid_key;
ALTER TABLE app.watch_event
  ADD CONSTRAINT watch_event_user_source_key UNIQUE (user_id, source_uuid);
