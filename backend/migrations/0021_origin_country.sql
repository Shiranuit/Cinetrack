-- Origin-country facet for filtering (Discover + Library). Original language is
-- already a column; this adds the country (TheTVDB `originalCountry`, e.g. "usa",
-- "jpn"). Spoken-language / production-country are NOT stored — TheTVDB's v4 API
-- returns them null. Idempotent (safe to re-run after a partial apply).
ALTER TABLE catalog.series ADD COLUMN IF NOT EXISTS original_country text;
ALTER TABLE catalog.movie  ADD COLUMN IF NOT EXISTS original_country text;

UPDATE catalog.series SET original_country = nullif(raw->>'originalCountry', '')
  WHERE original_country IS NULL AND raw ? 'originalCountry';
UPDATE catalog.movie SET original_country = nullif(raw->>'originalCountry', '')
  WHERE original_country IS NULL AND raw ? 'originalCountry';

CREATE INDEX IF NOT EXISTS series_orig_lang_idx    ON catalog.series (original_language);
CREATE INDEX IF NOT EXISTS series_orig_country_idx ON catalog.series (original_country);
CREATE INDEX IF NOT EXISTS movie_orig_lang_idx     ON catalog.movie (original_language);
CREATE INDEX IF NOT EXISTS movie_orig_country_idx  ON catalog.movie (original_country);

-- Score-ordered browse index (+ id tiebreaker) so deep offset pages stay fast.
CREATE INDEX IF NOT EXISTS series_score_id_idx ON catalog.series (score DESC NULLS LAST, id DESC) WHERE NOT deleted;
CREATE INDEX IF NOT EXISTS movie_score_id_idx  ON catalog.movie (score DESC NULLS LAST, id DESC) WHERE NOT deleted;
