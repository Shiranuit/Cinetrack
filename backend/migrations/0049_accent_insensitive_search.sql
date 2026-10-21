-- One canonical representation for indexed search and input normalization.
-- Pin the standard dictionary so folding does not depend on search_path. Its
-- rules are treated as fixed; changing them requires rebuilding these indexes.
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;

CREATE FUNCTION catalog.fold_search_text(title text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT lower(public.unaccent('public.unaccent'::regdictionary,
    normalize(coalesce(title, ''), NFC)))
$$;

-- Exact-title indexes must be rebuilt when their immutable key changes.
CREATE OR REPLACE FUNCTION catalog.search_title_key(title text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(catalog.fold_search_text(title), '[^[:alnum:]]+', ' ', 'g'))
$$;
REINDEX INDEX catalog.series_exact_title_idx;
REINDEX INDEX catalog.movie_exact_title_idx;
REINDEX INDEX catalog.translation_exact_title_idx;
REINDEX INDEX catalog.alias_exact_title_idx;

-- Replace raw-name indexes with expression indexes used by every word lookup.
-- Display names remain untouched. Episode translations remain excluded.
DROP INDEX catalog.series_name_trgm;
DROP INDEX catalog.movie_name_trgm;
DROP INDEX catalog.translation_search_idx;
DROP INDEX catalog.entity_alias_name_trgm;
CREATE INDEX series_name_trgm ON catalog.series USING gin (catalog.fold_search_text(name) gin_trgm_ops);
CREATE INDEX movie_name_trgm ON catalog.movie USING gin (catalog.fold_search_text(name) gin_trgm_ops);
CREATE INDEX translation_search_idx ON catalog.translation
  USING gin (entity_type, language, catalog.fold_search_text(name) gin_trgm_ops)
  WHERE entity_type <> 'episode';
CREATE INDEX entity_alias_name_trgm ON catalog.entity_alias
  USING gin (entity_type, language, catalog.fold_search_text(name) gin_trgm_ops);

-- Rebuild the persisted baseline once using the same folded words as search.
-- Later startups still only load the saved snapshot.
CREATE OR REPLACE FUNCTION catalog.refresh_search_word_baseline() RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
  term_count bigint;
BEGIN
  PERFORM set_config('work_mem', '64MB', true);
  DELETE FROM catalog.search_word_baseline;

  INSERT INTO catalog.search_word_baseline (kind, language, term, matches, titles)
  WITH entities AS MATERIALIZED (
    SELECT 'series'::text AS kind, id, name, original_language FROM catalog.series WHERE NOT deleted
    UNION ALL
    SELECT 'movie'::text AS kind, id, name, original_language FROM catalog.movie WHERE NOT deleted
  ), names AS MATERIALIZED (
    SELECT kind, id, '*'::text AS language, name FROM entities WHERE name IS NOT NULL
    UNION ALL
    SELECT e.kind, e.id, l.language, t.name
    FROM catalog.translation t JOIN entities e ON e.kind = t.entity_type AND e.id = t.entity_id
    CROSS JOIN LATERAL unnest(CASE WHEN t.language = e.original_language
      THEN ARRAY[t.language, '*'] ELSE ARRAY[t.language] END) l(language)
    WHERE t.entity_type IN ('series', 'movie') AND t.name IS NOT NULL
    UNION ALL
    SELECT e.kind, e.id, l.language, a.name
    FROM catalog.entity_alias a JOIN entities e ON e.kind = a.entity_type AND e.id = a.entity_id
    CROSS JOIN LATERAL unnest(CASE WHEN a.language = e.original_language
      THEN ARRAY[a.language, '*'] ELSE ARRAY[a.language] END) l(language)
    WHERE a.language IS NOT NULL
  ), populations AS (
    SELECT kind, language, count(DISTINCT id) AS titles FROM names GROUP BY kind, language
  ), frequencies AS (
    SELECT kind COLLATE "C" AS kind, language COLLATE "C" AS language,
      term COLLATE "C" AS term, count(DISTINCT id) AS matches
    FROM names
    CROSS JOIN LATERAL regexp_split_to_table(catalog.fold_search_text(name), '[^[:alnum:]]+') w(word)
    -- Count distinct titles across repeated words, aliases and 3-letter prefixes.
    CROSS JOIN LATERAL unnest(CASE WHEN char_length(word) > 3
      THEN ARRAY[word, left(word, 3)] ELSE ARRAY[word] END) terms(term)
    WHERE word <> ''
    GROUP BY 1, 2, 3
  )
  SELECT f.kind, f.language, f.term, f.matches, p.titles
  FROM frequencies f JOIN populations p USING (kind, language)
  WHERE f.matches >= 5000 AND f.matches::double precision >= p.titles * 0.02;

  GET DIAGNOSTICS term_count = ROW_COUNT;
  RETURN term_count;
END;
$$;

SELECT catalog.refresh_search_word_baseline();
