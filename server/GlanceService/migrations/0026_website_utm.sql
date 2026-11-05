-- Whitelisted campaign parameters only (normalized slugs). Never full URLs,
-- referrers or other query parameters.
ALTER TABLE website_events ADD COLUMN utm_source TEXT;
ALTER TABLE website_events ADD COLUMN utm_medium TEXT;
ALTER TABLE website_events ADD COLUMN utm_campaign TEXT;
ALTER TABLE website_events ADD COLUMN utm_content TEXT;
