-- Convert app.users.id (and every FK column referencing it) from bigint to uuid.
-- User identifiers are sensitive/enumerable as sequential ints; UUIDv7 (generated
-- app-side on registration) is non-guessable. Catalog ids (series/movie/episode)
-- stay bigint — they're TheTVDB ids.
--
-- `ALTER COLUMN ... TYPE` auto-rebuilds dependent primary keys and indexes, so we
-- don't have to drop/recreate them. A temp mapping function bridges each existing
-- bigint id to a fresh uuid (subqueries aren't allowed directly in USING, but a
-- function call is).

CREATE TEMP TABLE _umap AS SELECT id AS old, gen_random_uuid() AS new FROM app.users;
CREATE FUNCTION pg_temp._mapu(bigint) RETURNS uuid AS $$ SELECT new FROM _umap WHERE old = $1 $$ LANGUAGE sql STABLE;

-- 1) Drop every FK to app.users(id) (types must match to retype).
ALTER TABLE app.audit_log       DROP CONSTRAINT audit_log_user_id_fkey;
ALTER TABLE app.episode_rating  DROP CONSTRAINT episode_rating_user_id_fkey;
ALTER TABLE app.episode_rewatch DROP CONSTRAINT episode_rewatch_user_id_fkey;
ALTER TABLE app.import_match     DROP CONSTRAINT import_match_user_id_fkey;
ALTER TABLE app.invitation      DROP CONSTRAINT invitation_created_by_fkey;
ALTER TABLE app.invitation      DROP CONSTRAINT invitation_used_by_fkey;
ALTER TABLE app.list            DROP CONSTRAINT list_user_id_fkey;
ALTER TABLE app.password_reset  DROP CONSTRAINT password_reset_user_id_fkey;
ALTER TABLE app.session         DROP CONSTRAINT session_user_id_fkey;
ALTER TABLE app.user_follow     DROP CONSTRAINT user_follow_followee_id_fkey;
ALTER TABLE app.user_follow     DROP CONSTRAINT user_follow_follower_id_fkey;
ALTER TABLE app.user_movie      DROP CONSTRAINT user_movie_user_id_fkey;
ALTER TABLE app.user_show       DROP CONSTRAINT user_show_user_id_fkey;
ALTER TABLE app.watch_event     DROP CONSTRAINT watch_event_user_id_fkey;
-- Self-reference CHECK compares the two user columns; it breaks while one is uuid
-- and the other is still bigint, so drop it and re-add after both are retyped.
ALTER TABLE app.user_follow     DROP CONSTRAINT user_follow_check;

-- 2) Retype the primary key.
ALTER TABLE app.users ALTER COLUMN id DROP DEFAULT;
ALTER TABLE app.users ALTER COLUMN id TYPE uuid USING pg_temp._mapu(id);
ALTER TABLE app.users ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 3) Retype every FK column via the same mapping.
ALTER TABLE app.audit_log       ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.episode_rating  ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.episode_rewatch ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.import_match     ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.invitation      ALTER COLUMN created_by  TYPE uuid USING pg_temp._mapu(created_by);
ALTER TABLE app.invitation      ALTER COLUMN used_by     TYPE uuid USING pg_temp._mapu(used_by);
ALTER TABLE app.list            ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.password_reset  ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.session         ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.user_follow     ALTER COLUMN followee_id TYPE uuid USING pg_temp._mapu(followee_id);
ALTER TABLE app.user_follow     ALTER COLUMN follower_id TYPE uuid USING pg_temp._mapu(follower_id);
ALTER TABLE app.user_movie      ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.user_show       ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);
ALTER TABLE app.watch_event     ALTER COLUMN user_id     TYPE uuid USING pg_temp._mapu(user_id);

-- 4) Re-add the FKs (same delete behaviour as before).
ALTER TABLE app.audit_log       ADD CONSTRAINT audit_log_user_id_fkey       FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE SET NULL;
ALTER TABLE app.episode_rating  ADD CONSTRAINT episode_rating_user_id_fkey  FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.episode_rewatch ADD CONSTRAINT episode_rewatch_user_id_fkey FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.import_match     ADD CONSTRAINT import_match_user_id_fkey    FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.invitation      ADD CONSTRAINT invitation_created_by_fkey   FOREIGN KEY (created_by)  REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.invitation      ADD CONSTRAINT invitation_used_by_fkey      FOREIGN KEY (used_by)     REFERENCES app.users(id) ON DELETE SET NULL;
ALTER TABLE app.list            ADD CONSTRAINT list_user_id_fkey            FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.password_reset  ADD CONSTRAINT password_reset_user_id_fkey  FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.session         ADD CONSTRAINT session_user_id_fkey         FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.user_follow     ADD CONSTRAINT user_follow_followee_id_fkey FOREIGN KEY (followee_id) REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.user_follow     ADD CONSTRAINT user_follow_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.user_movie      ADD CONSTRAINT user_movie_user_id_fkey      FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.user_show       ADD CONSTRAINT user_show_user_id_fkey       FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.watch_event     ADD CONSTRAINT watch_event_user_id_fkey     FOREIGN KEY (user_id)     REFERENCES app.users(id) ON DELETE CASCADE;
ALTER TABLE app.user_follow     ADD CONSTRAINT user_follow_check CHECK (follower_id <> followee_id);
