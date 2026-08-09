-- Opt-in: keep a caught-up show in "To watch" while it still has unaired episodes.
--
-- By default a show leaves "To watch" the moment you've seen its latest aired
-- episode, and only comes back when a new one airs — so a series you're actively
-- following disappears from the category you look at every day. With this on,
-- "Up to date" means caught up AND nothing more coming; everything else is
-- unchanged, including the drop to "Haven't watched in a while" after a month of
-- no watching and no new episodes.
--
-- Stored on the user (like is_private / languages / activity_visibility) so the
-- choice syncs across devices, and because the classification runs in SQL — see
-- `tracking::state::state_case`.
--
-- Defaults to FALSE: it changes where existing shows appear, so nobody's Library
-- rearranges itself under them without asking.
ALTER TABLE app.users
    ADD COLUMN IF NOT EXISTS keep_upcoming_in_to_watch BOOLEAN NOT NULL DEFAULT false;
