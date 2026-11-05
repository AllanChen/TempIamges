CREATE TABLE IF NOT EXISTS widget_publish_grants (
  widget_id TEXT NOT NULL,
  developer_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (widget_id, developer_id)
);

-- The local OSS Widget is administered centrally, but its developer may submit
-- new versions for the normal review flow. This grant does not allow release.
INSERT OR IGNORE INTO widget_publish_grants (widget_id, developer_id)
SELECT id, 'mock:glance-cli' FROM widgets
WHERE id = '55e64c7e-f079-448a-b5bd-7315b2589019' AND owner_id = 'admin';
