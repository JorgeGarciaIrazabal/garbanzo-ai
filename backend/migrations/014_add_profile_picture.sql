-- Store base64-encoded profile picture (downscaled JPEG, ~256x256).
ALTER TABLE users ADD COLUMN IF NOT EXISTS profile_picture_b64 TEXT;