-- Security audit trail: append-only record of auth-sensitive events (logins,
-- password changes/resets, registrations, invites, account deletion). `user_id`
-- is nullable + ON DELETE SET NULL so events survive (anonymized) after an account
-- is removed, and unknown-email login attempts can still be recorded globally.
CREATE TABLE IF NOT EXISTS app.audit_log (
  id          bigserial PRIMARY KEY,
  user_id     bigint REFERENCES app.users(id) ON DELETE SET NULL,
  event       text NOT NULL,
  ip          text,
  detail      jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_log_user_idx ON app.audit_log (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_log_event_idx ON app.audit_log (event, created_at DESC);
