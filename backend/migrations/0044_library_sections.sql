-- Per-user Library layout: which sections the Library shows, in what order, and
-- user-defined sections carrying their own saved filter.
--
-- Unlike `profile_blocks` (0028/0043), this can't be a `text[]` on app.users: a
-- custom section carries a title and a filter of its own, and ordering has to
-- interleave built-in and custom sections, so both need to live in one ordered
-- list. One row per section, ordered by `position`.
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
  -- One of the fixed categories the Library computes ('watching', 'stale', ...),
  -- or NULL for a user-defined section.
  builtin   TEXT,
  -- Custom sections only: the user's label for the rail.
  title     TEXT,
  -- Custom sections only: the saved filter, stored as the flat query-param map the
  -- Library filter endpoint already speaks (`{"type":"series","genres":"12,45"}`),
  -- so rendering a custom rail is just `/api/library/filter` with these params —
  -- no second filter language to keep in sync with `DiscoverQuery`.
  filters   JSONB,
  -- Hidden sections stay in the list (keeping their place in the order) so turning
  -- one back on restores it where the user had put it.
  enabled   BOOLEAN NOT NULL DEFAULT true,
  PRIMARY KEY (user_id, id),

  -- A section is EITHER built-in OR custom, never both and never neither — the
  -- read path picks its branch on `builtin IS NULL` and has no third case.
  CONSTRAINT library_section_shape CHECK (
    (builtin IS NOT NULL AND title IS NULL AND filters IS NULL)
    OR (builtin IS NULL AND title IS NOT NULL AND filters IS NOT NULL)
  ),
  -- Reject unknown built-ins at the DB level: the client renders a built-in by
  -- looking its key up in a fixed map, so an unrecognized one would be an
  -- invisible, unremovable row in the user's layout.
  CONSTRAINT library_section_builtin_known CHECK (
    builtin IS NULL OR builtin IN
      ('watching', 'stale', 'not_started', 'for_later', 'up_to_date', 'stopped', 'movies')
  ),
  -- Custom sections carry a filter object, not a scalar or an array.
  CONSTRAINT library_section_filters_object CHECK (
    filters IS NULL OR jsonb_typeof(filters) = 'object'
  )
);

-- The read path is always "this user's sections in order".
CREATE INDEX library_section_user_idx ON app.library_section (user_id, position);

-- A built-in category can appear at most once per user (a custom section can be
-- duplicated freely — two saved filters may legitimately share a name).
CREATE UNIQUE INDEX library_section_builtin_uniq
  ON app.library_section (user_id, builtin) WHERE builtin IS NOT NULL;
