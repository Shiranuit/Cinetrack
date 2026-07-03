-- Local, alias-aware, ranked search over the mirror so it works across ALL
-- languages (not just the caller's translation) and without TheTVDB.
--
-- We use pg_trgm (trigram) rather than tsvector FTS: titles are short and
-- multilingual (incl. romaji/CJK), where stemming-based FTS misfires and partial
-- input needs prefix hacks. Trigram similarity is language-agnostic, substring/
-- typo tolerant, and gives a natural 0..1 rank via word_similarity().
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- All alias names for a title (every language variant TheTVDB knows), so a match
-- on any of them surfaces the show. Backfilled from the mirrored raw payloads.
ALTER TABLE catalog.series ADD COLUMN aliases text[] NOT NULL DEFAULT '{}';
ALTER TABLE catalog.movie  ADD COLUMN aliases text[] NOT NULL DEFAULT '{}';

UPDATE catalog.series SET aliases = COALESCE(
  (SELECT array_agg(DISTINCT a->>'name')
   FROM jsonb_array_elements(raw->'aliases') a
   WHERE nullif(a->>'name', '') IS NOT NULL), '{}')
WHERE jsonb_typeof(raw->'aliases') = 'array';

UPDATE catalog.movie SET aliases = COALESCE(
  (SELECT array_agg(DISTINCT a->>'name')
   FROM jsonb_array_elements(raw->'aliases') a
   WHERE nullif(a->>'name', '') IS NOT NULL), '{}')
WHERE jsonb_typeof(raw->'aliases') = 'array';

-- Denormalized search document (base name + every alias). Maintained by a
-- trigger rather than a GENERATED column because array_to_string is only STABLE,
-- not IMMUTABLE, so it can't appear in a generation expression.
ALTER TABLE catalog.series ADD COLUMN search_text text;
ALTER TABLE catalog.movie  ADD COLUMN search_text text;

CREATE OR REPLACE FUNCTION catalog.set_search_text() RETURNS trigger AS $$
BEGIN
  NEW.search_text := coalesce(NEW.name, '') || ' ' || array_to_string(NEW.aliases, ' ');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER series_search_text BEFORE INSERT OR UPDATE OF name, aliases
  ON catalog.series FOR EACH ROW EXECUTE FUNCTION catalog.set_search_text();
CREATE TRIGGER movie_search_text BEFORE INSERT OR UPDATE OF name, aliases
  ON catalog.movie FOR EACH ROW EXECUTE FUNCTION catalog.set_search_text();

-- Backfill existing rows (the trigger only fires on future writes).
UPDATE catalog.series SET search_text = coalesce(name, '') || ' ' || array_to_string(aliases, ' ');
UPDATE catalog.movie  SET search_text = coalesce(name, '') || ' ' || array_to_string(aliases, ' ');

CREATE INDEX series_search_trgm ON catalog.series USING gin (search_text gin_trgm_ops);
CREATE INDEX movie_search_trgm ON catalog.movie USING gin (search_text gin_trgm_ops);
-- Translations hold the caller-language display names; index them too so an
-- exact-language name that isn't among the aliases is still findable.
CREATE INDEX translation_name_trgm ON catalog.translation USING gin (name gin_trgm_ops);
