-- Private profiles + friend-request flow. A follow of a public user is
-- auto-accepted; following a PRIVATE user creates a 'pending' request the owner
-- must accept before the follower can see the profile.
ALTER TABLE app.users ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE app.user_follow ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'accepted'; -- 'pending' | 'accepted'
CREATE INDEX IF NOT EXISTS user_follow_followee_status_idx ON app.user_follow (followee_id, status);
