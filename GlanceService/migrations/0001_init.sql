CREATE TABLE IF NOT EXISTS widgets (
  id TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  name TEXT NOT NULL,
  summary TEXT NOT NULL,
  author TEXT NOT NULL,
  icon_url TEXT,
  current_version TEXT,
  status TEXT NOT NULL DEFAULT 'draft',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS widget_versions (
  id TEXT PRIMARY KEY,
  widget_id TEXT NOT NULL,
  version TEXT NOT NULL,
  manifest_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'submitted',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(widget_id, version)
);

CREATE TABLE IF NOT EXISTS widget_workers (
  id TEXT PRIMARY KEY,
  widget_id TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active',
  last_seen_at TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS widget_tasks (
  id TEXT PRIMARY KEY,
  widget_id TEXT NOT NULL,
  version_id TEXT NOT NULL,
  command_id TEXT NOT NULL,
  owner_id TEXT NOT NULL,
  type TEXT NOT NULL,
  input_json TEXT NOT NULL,
  parameters_json TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'queued',
  worker_id TEXT,
  lease_expires_at TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  result_json TEXT,
  error_code TEXT,
  created_at TEXT NOT NULL,
  claimed_at TEXT,
  completed_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_widget_tasks_pull ON widget_tasks(widget_id, status, created_at);

CREATE TABLE IF NOT EXISTS widget_assets (
  id TEXT PRIMARY KEY,
  widget_id TEXT,
  owner_id TEXT NOT NULL,
  object_key TEXT NOT NULL UNIQUE,
  mime_type TEXT NOT NULL,
  size_bytes INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT
);

CREATE TABLE IF NOT EXISTS widget_audit_logs (
  id TEXT PRIMARY KEY,
  widget_id TEXT NOT NULL,
  version_id TEXT,
  actor_id TEXT NOT NULL,
  action TEXT NOT NULL,
  previous_status TEXT,
  next_status TEXT,
  note TEXT,
  created_at TEXT NOT NULL
);
