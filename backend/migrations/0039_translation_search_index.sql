-- Faster catalog name search. The old plan BitmapAnd-ed a name-only trigram index
-- (which matched ALL entity types, 72% episodes, and ALL languages) with an
-- entity_type btree, then rechecked on a lossy heap bitmap. This composite trigram
-- index (btree_gin lets non-trgm columns lead a GIN index) filters entity_type +
-- language INSIDE the index, so the scan returns only relevant rows, no BitmapAnd,
-- no lossy recheck. Cut typical searches ~2-4x (e.g. "love" 75ms -> 19ms).
CREATE EXTENSION IF NOT EXISTS btree_gin;

-- Partial: episode translations (72% of the table) are only ever read by primary
-- key (the per-episode name overlay), never trigram-searched, so they're excluded.
-- Indexes ~1.4M rows instead of ~5M (97 MB vs 281 MB), and episode-translation
-- backfills no longer maintain a search index they don't use.
CREATE INDEX IF NOT EXISTS translation_search_idx
  ON catalog.translation USING gin (entity_type, language, name gin_trgm_ops)
  WHERE entity_type <> 'episode';

-- The name-only trigram index is now redundant: every search match also filters
-- entity_type + language, which the composite covers. Drop it so translation writes
-- (enrichment / backfills) don't maintain two big GIN indexes.
DROP INDEX IF EXISTS catalog.translation_name_trgm;
