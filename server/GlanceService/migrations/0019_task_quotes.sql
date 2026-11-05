-- Immutable, account-bound quotes. One quote can fund at most one task.
CREATE TABLE task_quotes (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  widget_id TEXT NOT NULL,
  version_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  snapshot_json TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX task_quotes_expiry ON task_quotes(expires_at);
ALTER TABLE widget_tasks ADD COLUMN quote_id TEXT REFERENCES task_quotes(id);
ALTER TABLE widget_tasks ADD COLUMN billing_verified_at TEXT;
CREATE UNIQUE INDEX widget_tasks_quote ON widget_tasks(quote_id) WHERE quote_id IS NOT NULL;
