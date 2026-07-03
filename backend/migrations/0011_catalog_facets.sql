-- Dedicated, indexable facet tables/columns for advanced filtering (Discover +
-- Library), populated from the series `/extended` payload in `series::upsert`.
-- Far cheaper than scanning `raw` JSONB per query.

-- Counts on the series row (season_count from raw seasons; episode_count filled
-- when the episode list is cached).
ALTER TABLE catalog.series ADD COLUMN IF NOT EXISTS season_count  INT;
ALTER TABLE catalog.series ADD COLUMN IF NOT EXISTS episode_count INT;

-- Themes / keywords (TheTVDB "tags"): `name` is the theme (e.g. "Love Triangle"),
-- `category` is its group (e.g. "Plot Characteristics").
CREATE TABLE IF NOT EXISTS catalog.tag (
  id        BIGINT PRIMARY KEY,
  name      TEXT NOT NULL,
  category  TEXT
);
CREATE TABLE IF NOT EXISTS catalog.series_tag (
  series_id BIGINT NOT NULL REFERENCES catalog.series(id) ON DELETE CASCADE,
  tag_id    BIGINT NOT NULL REFERENCES catalog.tag(id) ON DELETE CASCADE,
  PRIMARY KEY (series_id, tag_id)
);
CREATE INDEX IF NOT EXISTS series_tag_tag_idx ON catalog.series_tag (tag_id);

-- Companies (networks / studios / production). The `kind` (Network/Studio/…) is
-- per relationship — the same company can be a network for one show, studio for
-- another — so it lives on the join, not the company.
CREATE TABLE IF NOT EXISTS catalog.company (
  id    BIGINT PRIMARY KEY,
  name  TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS catalog.series_company (
  series_id  BIGINT NOT NULL REFERENCES catalog.series(id) ON DELETE CASCADE,
  company_id BIGINT NOT NULL REFERENCES catalog.company(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL,     -- 'Network' | 'Studio' | 'Production Company' | …
  PRIMARY KEY (series_id, company_id, kind)
);
CREATE INDEX IF NOT EXISTS series_company_lookup_idx ON catalog.series_company (kind, company_id);

-- Speed up the genre join filters (table already exists from 0001, now populated).
CREATE INDEX IF NOT EXISTS series_genre_genre_idx ON catalog.series_genre (genre_id);

-- Filter/sort helpers on the scalar columns.
CREATE INDEX IF NOT EXISTS series_year_idx    ON catalog.series (year);
CREATE INDEX IF NOT EXISTS series_score_idx   ON catalog.series (score);
CREATE INDEX IF NOT EXISTS series_status_idx  ON catalog.series (status);
