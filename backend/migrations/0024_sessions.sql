-- Refresh-token sessions. Access tokens are short-lived JWTs carrying a session
-- id (`sid`); the long-lived refresh token lives ONLY here (hashed) — in an
-- httpOnly cookie on web, secure storage on mobile. Rotated on every refresh;
-- reuse of a rotated token (theft) revokes the whole session.
CREATE TABLE IF NOT EXISTS app.session (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       bigint NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  refresh_hash  text NOT NULL,   -- sha256 hex of the CURRENT refresh token
  prev_hash     text,            -- previous token (one step back) for reuse detection
  device        text,            -- client/user-agent label
  ip            text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  last_used_at  timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  revoked       boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS session_user_idx ON app.session (user_id);
CREATE UNIQUE INDEX IF NOT EXISTS session_refresh_idx ON app.session (refresh_hash);
CREATE INDEX IF NOT EXISTS session_prev_idx ON app.session (prev_hash) WHERE prev_hash IS NOT NULL;
