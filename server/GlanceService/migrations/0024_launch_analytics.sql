-- Website sessions are random, tab-scoped IDs; never join them to Mac/account identity.
CREATE TABLE website_events (
  session_id TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
  page TEXT NOT NULL, language TEXT NOT NULL, target TEXT, placement TEXT,
  created_at TEXT NOT NULL, PRIMARY KEY(session_id,id)
);
CREATE INDEX website_events_date ON website_events(created_at,kind);
CREATE INDEX website_events_session ON website_events(session_id,kind,created_at);
CREATE INDEX billing_events_device_journey ON billing_events(device_hash,journey_id,kind,created_at);

-- Preserve old events as unknown; never count sandbox offer views as production conversion opportunities.
ALTER TABLE billing_events ADD COLUMN billing_mode TEXT;
