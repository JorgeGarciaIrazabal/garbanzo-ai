-- Optional coarse location for the dynamic <context> block (IDEAS.md idea 3).
-- Holds a human-readable "City, Country" string — NEVER raw coordinates. The
-- client either sends coordinates once to POST /auth/me/location (the server
-- reverse-geocodes city-level via Nominatim and stores only the result) or
-- types the city manually via PATCH /auth/me. NULL = the user hasn't opted
-- in (the settings toggle defaults off), and the context block omits the
-- location line entirely.
ALTER TABLE users ADD COLUMN IF NOT EXISTS location VARCHAR(128) DEFAULT NULL;
