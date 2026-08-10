-- Each Library category carries its own default sort.
--
-- One account-wide default can't express what the categories actually mean: "To
-- watch" wants whatever just aired, "Stopped" wants alphabetical, "Movies" wants
-- your rating. So the sort belongs to the category, configured in the same place
-- you reorder and hide them.
--
-- The column defaults are only a safety net for rows inserted by an older build.
-- Existing rows are backfilled below, because a user who has already customized
-- their layout would otherwise get 'last_watched' everywhere instead of the seeds.
--
-- Not CHECK-constrained: the set of sort keys changes with the app. It is validated
-- in Rust on write (`tracking::LIBRARY_SORTS` / `MOVIE_SORTS`) and falls back to the
-- seed on read, so an unknown key can never reach an ORDER BY.
ALTER TABLE app.library_section
    ADD COLUMN IF NOT EXISTS sort      TEXT    NOT NULL DEFAULT 'last_watched',
    ADD COLUMN IF NOT EXISTS sort_desc BOOLEAN NOT NULL DEFAULT true;

-- Seeds, mirroring `tracking::sections::SECTION_SORT_SEEDS`.
UPDATE app.library_section SET sort = 'last_aired',   sort_desc = true  WHERE builtin = 'watching';
UPDATE app.library_section SET sort = 'last_watched', sort_desc = true  WHERE builtin = 'stale';
UPDATE app.library_section SET sort = 'last_watched', sort_desc = true  WHERE builtin = 'up_to_date';
UPDATE app.library_section SET sort = 'name',         sort_desc = false WHERE builtin = 'not_started';
UPDATE app.library_section SET sort = 'name',         sort_desc = false WHERE builtin = 'for_later';
UPDATE app.library_section SET sort = 'name',         sort_desc = false WHERE builtin = 'stopped';
UPDATE app.library_section SET sort = 'my_rating',    sort_desc = true  WHERE builtin = 'movies';
