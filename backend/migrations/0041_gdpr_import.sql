-- Tie every episode watch a GDPR import creates back to the import run that made it,
-- so re-importing can cleanly REPLACE its own prior events (delete the old batch,
-- insert the new one) without disturbing watches the user added by hand in the app.
--
-- Why the existing key isn't enough: watch_event.source_uuid (see 0008) only dedupes
-- when the SAME export is re-imported. TV Time changed its export's id scheme between
-- versions (the newer export dropped the `episode_id`/uuid columns for a short `ep_id`
-- and a differently-shaped `key`), so across formats the source_uuid no longer matches
-- a prior import and a naive re-import would duplicate the whole history. An explicit
-- import batch decouples idempotency from the export's (unstable) identifiers.
--
-- Scope: episodes only. Movie watch events already carry a deterministic source_uuid
-- ('movie-import-'||uuid) that is stable across export versions, so they self-dedupe
-- and need no batching.
CREATE TABLE app.gdpr_import (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  imported_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  filename     TEXT,                             -- source zip name, when known
  watch_events INT  NOT NULL DEFAULT 0,          -- episode events attributed to this run
  is_legacy    BOOLEAN NOT NULL DEFAULT false,   -- retro-tagged by heuristic, not a real run
  note         TEXT
);
CREATE INDEX gdpr_import_user_idx ON app.gdpr_import (user_id);

-- NULL import_id == "not from any import" == a manual watch, which the re-import
-- delete step must never touch. ON DELETE CASCADE lets deleting a batch drop its
-- events in one shot.
ALTER TABLE app.watch_event
  ADD COLUMN import_id UUID REFERENCES app.gdpr_import(id) ON DELETE CASCADE;
CREATE INDEX watch_event_import_idx ON app.watch_event (import_id) WHERE import_id IS NOT NULL;
