-- Give invitations a stable, non-enumerable id (for listing + revoking) and store
-- the plaintext code so an unused invite's link can be shown/copied later.
-- Invites are single-use and low-sensitivity, so storing the code is an acceptable
-- tradeoff for the copy-link feature (the code_hash stays the source of truth for
-- validation at sign-up).
ALTER TABLE app.invitation ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE app.invitation ADD COLUMN IF NOT EXISTS code text;
CREATE UNIQUE INDEX IF NOT EXISTS invitation_id_key ON app.invitation (id);
