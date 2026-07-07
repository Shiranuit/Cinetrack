-- Language-tagged aliases, so search can restrict them to the user's languages
-- (like translated titles) instead of matching a language-less blob. They can't
-- live in catalog.translation (its PK is one name per (entity, language), but a
-- language can have many aliases), so they get their own table. The flat
-- catalog.series/movie.aliases column stays, it still powers the "also known as"
-- display; it's just no longer part of the search document.
CREATE TABLE catalog.entity_alias (
  entity_type text   NOT NULL,   -- 'series' | 'movie'
  entity_id   bigint NOT NULL,
  language    text,              -- alias language (nullable; unknown = not user-filterable)
  name        text   NOT NULL
);
CREATE INDEX entity_alias_entity_idx ON catalog.entity_alias (entity_type, entity_id);
CREATE INDEX entity_alias_name_trgm  ON catalog.entity_alias USING gin (name gin_trgm_ops);

-- Backfill from each record's raw `aliases` array (carries {name, language}).
INSERT INTO catalog.entity_alias (entity_type, entity_id, language, name)
SELECT 'series', s.id, NULLIF(a->>'language',''), a->>'name'
FROM catalog.series s CROSS JOIN LATERAL jsonb_array_elements(s.raw->'aliases') a
WHERE jsonb_typeof(s.raw->'aliases') = 'array' AND a->>'name' IS NOT NULL;

INSERT INTO catalog.entity_alias (entity_type, entity_id, language, name)
SELECT 'movie', m.id, NULLIF(a->>'language',''), a->>'name'
FROM catalog.movie m CROSS JOIN LATERAL jsonb_array_elements(m.raw->'aliases') a
WHERE jsonb_typeof(m.raw->'aliases') = 'array' AND a->>'name' IS NOT NULL;

-- Search document is now the base name only; aliases are matched (language-filtered)
-- via catalog.entity_alias instead.
CREATE OR REPLACE FUNCTION catalog.set_search_text() RETURNS trigger AS $$
BEGIN
  NEW.search_text := coalesce(NEW.name, '');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

UPDATE catalog.series SET search_text = coalesce(name, '');
UPDATE catalog.movie  SET search_text = coalesce(name, '');
