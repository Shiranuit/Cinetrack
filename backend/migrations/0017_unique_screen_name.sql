-- Usernames must be unique, case-insensitively (so "Test" and "test" can't
-- both exist). A functional unique index on lower(screen_name) enforces this.
CREATE UNIQUE INDEX users_screen_name_lower_key ON app.users (lower(screen_name));
