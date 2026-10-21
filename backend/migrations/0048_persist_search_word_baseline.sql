-- Compute this catalog snapshot once during migration, then load its small set
-- of broad terms at startup. Ordinary restarts must not repeat the full scan.
CREATE TABLE catalog.search_word_baseline (
  kind text NOT NULL,
  language text NOT NULL,
  term text NOT NULL,
  matches bigint NOT NULL,
  titles bigint NOT NULL,
  PRIMARY KEY (kind, language, term)
);

-- Also available to an administrator after a major catalog import. Refresh is
-- explicit; it is never called by normal startup or search requests. The caller's
-- transaction atomically replaces the snapshot, including an empty catalog.
CREATE FUNCTION catalog.refresh_search_word_baseline() RETURNS bigint
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
    CROSS JOIN LATERAL regexp_split_to_table(lower(name), '[^[:alnum:]]+') w(word)
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
