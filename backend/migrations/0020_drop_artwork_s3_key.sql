-- Artwork images are served straight from TheTVDB's CDN (the client loads
-- image_url directly); we no longer proxy/cache image bytes into object storage.
-- Drop the now-unused mirror key. Garage/object storage is retained for
-- user-uploaded avatars & covers only. (Re-add if strict offline images are
-- ever needed — see docs/thetvdb-sync-redesign.md §10a.)
ALTER TABLE catalog.artwork DROP COLUMN IF EXISTS s3_key;
