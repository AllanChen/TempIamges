CREATE TABLE IF NOT EXISTS widget_worker_grants (
  widget_id TEXT NOT NULL,
  developer_id TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (widget_id, developer_id)
);

-- Temporary grants for the mock developer used to run the existing local Widgets.
INSERT OR IGNORE INTO widget_worker_grants (widget_id, developer_id) VALUES
  ('55e64c7e-f079-448a-b5bd-7315b2589019', 'mock:glance-cli'),
  ('7cc3967a-60ac-4677-9817-72f57f5ef5fa', 'mock:glance-cli'),
  ('a0d3311a-b952-4831-8ee4-69f72c381a88', 'mock:glance-cli'),
  ('ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f', 'mock:glance-cli');
