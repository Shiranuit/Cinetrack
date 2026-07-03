-- Track the original TV Time user_id on our (freshly-assigned) app.users id, so
-- re-running the GDPR import dedupes to the same account (idempotent) rather than
-- creating a new user each time.
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS external_tvtime_id BIGINT;
CREATE UNIQUE INDEX IF NOT EXISTS users_external_tvtime_id_idx
  ON app.users (external_tvtime_id) WHERE external_tvtime_id IS NOT NULL;
