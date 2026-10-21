-- Broad/short Discover queries use normalized title equality instead of scanning
-- and ranking a large substring match set. Keep that fallback indexable across
-- base titles, translations and aliases, with the same normalization on input.
CREATE FUNCTION catalog.search_title_key(title text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(lower(coalesce(title, '')), '[^[:alnum:]]+', ' ', 'g'))
$$;

CREATE INDEX series_exact_title_idx ON catalog.series (catalog.search_title_key(name));
CREATE INDEX movie_exact_title_idx ON catalog.movie (catalog.search_title_key(name));
CREATE INDEX translation_exact_title_idx
  ON catalog.translation (entity_type, catalog.search_title_key(name), language)
  WHERE entity_type <> 'episode';
CREATE INDEX alias_exact_title_idx
  ON catalog.entity_alias (entity_type, catalog.search_title_key(name), language);
