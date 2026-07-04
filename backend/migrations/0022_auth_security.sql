-- Auth hardening: session invalidation + password reset + invitations.

-- Bumped on password change / reset / logout-all. Embedded in the JWT and checked
-- on every request, so old tokens stop working once it changes.
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS token_generation bigint NOT NULL DEFAULT 0;

-- One-time password-reset tokens. We store only a SHA-256 HASH of the token (like
-- a session secret), never the token itself — a DB leak can't be turned into a reset.
CREATE TABLE IF NOT EXISTS app.password_reset (
  token_hash  text PRIMARY KEY,
  user_id     bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  expires_at  timestamptz NOT NULL,
  used_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS password_reset_user_idx ON app.password_reset (user_id);

-- One-time invitation codes (hash-stored, same as resets). `email` is optional:
-- set when the invite was emailed, null for a copy-paste link.
CREATE TABLE IF NOT EXISTS app.invitation (
  code_hash   text PRIMARY KEY,
  created_by  bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  email       text,
  expires_at  timestamptz NOT NULL,
  used_by     bigint REFERENCES app.users(id) ON DELETE SET NULL,
  used_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS invitation_created_by_idx ON app.invitation (created_by);
