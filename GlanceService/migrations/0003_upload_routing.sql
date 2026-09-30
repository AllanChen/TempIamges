CREATE TABLE IF NOT EXISTS service_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

INSERT OR IGNORE INTO service_settings (key, value, updated_at)
VALUES ('location_upload_routing', '1', CURRENT_TIMESTAMP);
