-- Per-user control over who may see the watch-activity timeline (the shows and
-- movies you marked watched, newest first).
--
--   'everyone' — anyone who can see the profile
--   'friends'  — accepted followers only (the DEFAULT, incl. for existing users)
--   'only_me'  — nobody but the owner
--
-- This NARROWS visibility on top of `is_private` (0014): a private profile still
-- hides everything from non-followers regardless of this setting, and 'friends'
-- then means the same accepted-follower set that `profile_visible` uses.
ALTER TABLE app.users
    ADD COLUMN IF NOT EXISTS activity_visibility TEXT NOT NULL DEFAULT 'friends';

-- Reject unknown values at the DB level so the API can never store a setting the
-- read path doesn't understand (it fails closed, but a bad row would hide activity
-- with no way to tell why).
ALTER TABLE app.users
    DROP CONSTRAINT IF EXISTS users_activity_visibility_check;
ALTER TABLE app.users
    ADD CONSTRAINT users_activity_visibility_check
    CHECK (activity_visibility IN ('everyone', 'friends', 'only_me'));

-- Show the activity block on every profile by default. New accounts get it from
-- the default; existing users have it APPENDED (kept last, so whatever block order
-- they already chose is preserved) and only where it is actually missing, so this
-- is idempotent. Mirrors how 0028/0029 introduced the 'movies' block.
ALTER TABLE app.users
    ALTER COLUMN profile_blocks SET DEFAULT '{stats,favorites,shows,movies,activity}';

UPDATE app.users
    SET profile_blocks = profile_blocks || ARRAY['activity']
    WHERE NOT ('activity' = ANY(profile_blocks));

-- The timeline reads one user's events newest-first; watch_event_user_idx
-- (user_id, watched_at) from 0001 already serves that, so no new index is needed.
