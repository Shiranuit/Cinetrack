-- Per-user Library layout: which of the built-in sections the Library shows, and
-- in what order.
--
-- Unlike `profile_blocks` (0028/0043), this isn't a `text[]` on app.users: each
-- section carries its own enabled flag alongside its position, and a row per
-- section keeps "hidden but still in place" expressible without a second array to
-- keep in step. One row per section, ordered by `position`.
--
-- NO BACKFILL: a user with no rows here gets the built-in defaults from the API.
-- That keeps this cheap, and means a built-in added later shows up for everyone
-- who never customized (those who did get it appended, see `set_library_sections`).
CREATE TABLE app.library_section (
  user_id   UUID    NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  id        UUID    NOT NULL DEFAULT gen_random_uuid(),
  -- Display order, ascending. Not unique: the API rewrites the whole list on every
  -- save, so gaps/ties only need to be broken deterministically (by id) on read.
  position  INT     NOT NULL,
  -- One of the fixed categories the Library computes.
  builtin   TEXT    NOT NULL,
  -- Hidden sections stay in the list (keeping their place in the order) so turning
  -- one back on restores it where the user had put it.
  enabled   BOOLEAN NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, id),

  -- Reject unknown built-ins at the DB level: the client renders a section by
  -- looking its key up in a fixed map, so an unrecognized one would be an
  -- invisible, unremovable row in the user's layout.
  CONSTRAINT library_section_builtin_known CHECK (
    builtin IN
      ('watching', 'stale', 'not_started', 'for_later', 'up_to_date', 'stopped', 'movies')
  )
);

-- The read path is always "this user's sections in order".
CREATE INDEX library_section_user_idx ON app.library_section (user_id, position);

-- A category maps to one bucket of shows, so a second row for it would render the
-- same shows twice.
CREATE UNIQUE INDEX library_section_builtin_uniq
  ON app.library_section (user_id, builtin);
