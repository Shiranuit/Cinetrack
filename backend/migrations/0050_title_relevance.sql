-- Retrieval still uses the folded trigram/exact indexes. Rank only the title
-- variants that passed those predicates, taking the best variant per entity.
-- Query keys/terms are prepared once by the caller, using the same tokenizer.
CREATE FUNCTION catalog.title_relevance(title text, query_key text, terms text[])
RETURNS bigint LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
    title_key text := catalog.search_title_key(title);
    term text;
    prefix_matches integer := 0;
    whole_matches integer := 0;
    matched_chars integer := 0;
    term_count integer := cardinality(terms);
BEGIN
    IF title_key = query_key THEN
        RETURN 1000000;
    END IF;
    IF title_key = '' OR term_count = 0 THEN
        RETURN 0;
    END IF;
    FOREACH term IN ARRAY terms LOOP
        -- Spaces in the canonical key are word boundaries. strpos treats query
        -- text literally, without interpreting LIKE or regular-expression syntax.
        IF strpos(' ' || title_key, ' ' || term) > 0 THEN
            prefix_matches := prefix_matches + 1;
        END IF;
        IF strpos(' ' || title_key || ' ', ' ' || term || ' ') > 0 THEN
            whole_matches := whole_matches + 1;
        END IF;
        matched_chars := matched_chars + char_length(term);
    END LOOP;
    -- Boundaries and coverage reward complete, concise titles. A small phrase
    -- bonus keeps word order useful without excluding reordered/infix searches.
    -- Exact titles always outrank partial matches, regardless of popularity.
    RETURN 300000::bigint * prefix_matches / term_count
         + 100000::bigint * whole_matches / term_count
         + 400000::bigint * least(matched_chars, char_length(title_key)) / char_length(title_key)
         + CASE WHEN strpos(title_key, query_key) > 0 THEN 50000 ELSE 0 END
         + CASE WHEN starts_with(title_key, query_key) THEN 25000 ELSE 0 END;
END
$$;
