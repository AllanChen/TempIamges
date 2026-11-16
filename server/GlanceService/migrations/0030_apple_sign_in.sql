-- Sign in with Apple (required next to Google in the Mac App Store build).
-- `apple_id` is Apple's stable user identifier (the identity token's `sub`).
ALTER TABLE users ADD COLUMN apple_id TEXT;
CREATE UNIQUE INDEX users_apple_id ON users(apple_id) WHERE apple_id IS NOT NULL;
