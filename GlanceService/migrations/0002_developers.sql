CREATE TABLE IF NOT EXISTS developer_oauth_states (
  state_hash TEXT PRIMARY KEY,
  client_state TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  redirect_uri TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS developer_auth_codes (
  code_hash TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  email TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS developer_sessions (
  token_hash TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  email TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_developer_sessions_owner ON developer_sessions(owner_id);

CREATE TABLE IF NOT EXISTS widget_review_results (
  id TEXT PRIMARY KEY,
  task_id TEXT NOT NULL,
  widget_id TEXT NOT NULL,
  version_id TEXT NOT NULL,
  status TEXT NOT NULL,
  result_json TEXT,
  created_at TEXT NOT NULL
);

ALTER TABLE widget_tasks ADD COLUMN claim_token_hash TEXT;
