-- Keep the series name as it appeared in the TV Time export, so that when a
-- tracked series' TheTVDB id is dead/merged (404 → `unavailable`) we can search
-- TheTVDB by that name and re-point the user's tracking + history to the live id.
ALTER TABLE app.user_show ADD COLUMN IF NOT EXISTS import_name TEXT;
