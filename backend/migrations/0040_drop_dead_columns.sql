-- Drop columns that no longer carry information.
--
-- 1) catalog.translation.is_alias / is_primary: store_bundle now skips TheTVDB's
--    isAlias name-translations on ingest, so nothing writes a non-NULL value
--    anymore (all rows are NULL) and no code reads them. Removed.
--
-- 2) catalog.{series,movie}.search_text: migration 0038 moved aliases out of the
--    search document into catalog.entity_alias, leaving search_text an exact copy
--    of name. Collapse it onto name: index name with pg_trgm and drop the redundant
--    column, its maintenance trigger + function, and its GIN index. Search now
--    matches / ranks on name directly (same result, one less column to maintain).

-- --- translation: drop the always-NULL flags -------------------------------
ALTER TABLE catalog.translation DROP COLUMN IF EXISTS is_alias;
ALTER TABLE catalog.translation DROP COLUMN IF EXISTS is_primary;

-- --- series/movie: collapse search_text onto name --------------------------
-- Trigram index on the base name (search now matches ILIKE and ranks with
-- word_similarity on name directly, the way it did on search_text).
CREATE INDEX IF NOT EXISTS series_name_trgm ON catalog.series USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS movie_name_trgm  ON catalog.movie  USING gin (name gin_trgm_ops);

-- Retire the search_text maintenance trigger + function (name needs no derivation).
DROP TRIGGER IF EXISTS series_search_text ON catalog.series;
DROP TRIGGER IF EXISTS movie_search_text  ON catalog.movie;
DROP FUNCTION IF EXISTS catalog.set_search_text();

-- Drop the old search_text GIN indexes and the column itself.
DROP INDEX IF EXISTS catalog.series_search_trgm;
DROP INDEX IF EXISTS catalog.movie_search_trgm;
ALTER TABLE catalog.series DROP COLUMN IF EXISTS search_text;
ALTER TABLE catalog.movie  DROP COLUMN IF EXISTS search_text;
