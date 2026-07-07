-- Populate catalog.artwork from the `artworks` array embedded in each series/movie
-- `raw` record, so the artwork gallery reads normalized, indexed rows (by series_id
-- / movie_id) instead of parsing JSONB on every request. Ongoing population is done
-- by catalog::artwork::store_for on each series/movie upsert; this backfills what's
-- already mirrored. Idempotent (artwork id is the PK; ON CONFLICT DO NOTHING).
INSERT INTO catalog.artwork
  (id, series_id, type, language, image_url, thumbnail_url, width, height, score, last_synced_at)
SELECT (a->>'id')::bigint, s.id, (a->>'type')::int, NULLIF(a->>'language',''),
       a->>'image', a->>'thumbnail', (a->>'width')::int, (a->>'height')::int,
       (a->>'score')::double precision, now()
FROM catalog.series s
CROSS JOIN LATERAL jsonb_array_elements(s.raw->'artworks') a
WHERE jsonb_typeof(s.raw->'artworks') = 'array'
  AND a->>'id' IS NOT NULL AND a->>'image' IS NOT NULL
ON CONFLICT (id) DO NOTHING;

INSERT INTO catalog.artwork
  (id, movie_id, type, language, image_url, thumbnail_url, width, height, score, last_synced_at)
SELECT (a->>'id')::bigint, m.id, (a->>'type')::int, NULLIF(a->>'language',''),
       a->>'image', a->>'thumbnail', (a->>'width')::int, (a->>'height')::int,
       (a->>'score')::double precision, now()
FROM catalog.movie m
CROSS JOIN LATERAL jsonb_array_elements(m.raw->'artworks') a
WHERE jsonb_typeof(m.raw->'artworks') = 'array'
  AND a->>'id' IS NOT NULL AND a->>'image' IS NOT NULL
ON CONFLICT (id) DO NOTHING;
