-- Mirror sync infrastructure (see docs/thetvdb-sync-redesign.md).
--
-- fetch_queue: work items for the enrichment worker — series/movies/etc. that
-- need a full /extended fetch (new stubs, or entities the /updates feed says
-- changed since our per-row last_synced_at). PRIMARY KEY(entity_type,id) dedups
-- duplicate notifications for the same entity into one row; the queue is drained
-- with FOR UPDATE SKIP LOCKED and rows are DELETEd on success (queue = pending
-- only), so it stays small and hot.
CREATE TABLE catalog.fetch_queue (
    entity_type       text        NOT NULL,   -- 'series' | 'movie' | 'season' | 'episode'
    id                bigint       NOT NULL,
    reason            text,                    -- 'stub' | 'update' | 'crawl' | 'merge' (advisory)
    source_updated_at timestamptz,            -- feed timeStamp that enqueued it (advisory)
    attempts          int         NOT NULL DEFAULT 0,
    enqueued_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (entity_type, id)
);

-- FIFO-ish drain order.
CREATE INDEX fetch_queue_enqueued_idx ON catalog.fetch_queue (enqueued_at);

-- crawl_state: resumable cursor for the full-scope seed crawl over
-- /series?page=N and /movies?page=N.
CREATE TABLE catalog.crawl_state (
    entity_type text        NOT NULL PRIMARY KEY, -- 'series' | 'movie'
    next_page   int         NOT NULL DEFAULT 0,
    done        boolean     NOT NULL DEFAULT false,
    updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Fast discovery of un-enriched stubs (last_synced_at pinned to the epoch by
-- store_stub) so the enrichment worker can enqueue them cheaply.
CREATE INDEX series_stub_idx ON catalog.series (id) WHERE last_synced_at = to_timestamp(0);
CREATE INDEX movie_stub_idx  ON catalog.movie  (id) WHERE last_synced_at = to_timestamp(0);
