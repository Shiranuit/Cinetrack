-- Durably cache TheTVDB's raw name/overview translation bundle per series & movie.
-- TheTVDB's `?meta=translations` nameTranslations[] mixes the real translated name
-- with aliases (isAlias:true romanizations); we derive the display name from it. If
-- we ever change that derivation, we want to re-run from local data instead of
-- re-querying all of TheTVDB. The base record's `raw` can't serve this: the routine
-- /updates sync overwrites `raw` with the base record (no bundle). This column is
-- written ONLY by translation::store_bundle, so ordinary syncs leave it intact.
--
-- Cold storage (never read in hot query paths); JSONB is TOAST-compressed out of line.
ALTER TABLE catalog.series ADD COLUMN IF NOT EXISTS raw_translations JSONB;
ALTER TABLE catalog.movie  ADD COLUMN IF NOT EXISTS raw_translations JSONB;
