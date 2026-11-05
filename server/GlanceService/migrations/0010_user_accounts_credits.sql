CREATE TABLE users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE,
  google_id TEXT UNIQUE,
  name TEXT,
  avatar_url TEXT,
  auth_provider TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  credits INTEGER NOT NULL DEFAULT 0 CHECK (credits >= 0 AND credits <= 1000000000),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_login_at TEXT
);
CREATE TABLE user_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_user_sessions_user ON user_sessions(user_id);
CREATE TABLE user_email_codes (
  email TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  expires_at TEXT NOT NULL,
  sent_at TEXT NOT NULL
);
CREATE TABLE user_auth_limits (
  key TEXT PRIMARY KEY,
  count INTEGER NOT NULL,
  window_start INTEGER NOT NULL
);
CREATE TABLE user_oauth_states (
  state_hash TEXT PRIMARY KEY,
  client_state TEXT NOT NULL,
  code_challenge TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE TABLE user_auth_codes (
  code_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  code_challenge TEXT NOT NULL,
  expires_at TEXT NOT NULL
);
CREATE TABLE user_credit_ledger (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  amount INTEGER NOT NULL,
  reason TEXT NOT NULL,
  task_id TEXT UNIQUE,
  actor_id TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_credit_ledger_user ON user_credit_ledger(user_id, created_at);
CREATE TRIGGER apply_user_credit_entry AFTER INSERT ON user_credit_ledger
BEGIN
  UPDATE users SET credits=credits+NEW.amount,updated_at=NEW.created_at WHERE id=NEW.user_id;
END;

ALTER TABLE widget_tasks ADD COLUMN credit_cost INTEGER NOT NULL DEFAULT 1;
ALTER TABLE widget_tasks ADD COLUMN request_key TEXT;
ALTER TABLE widget_tasks ADD COLUMN request_hash TEXT;
CREATE UNIQUE INDEX idx_task_request_key ON widget_tasks(owner_id, request_key) WHERE request_key IS NOT NULL;

-- Creating a production task and charging its owner are one SQLite statement.
-- Any failure rolls back the task, balance change, and ledger entry together.
CREATE TRIGGER charge_widget_task AFTER INSERT ON widget_tasks
WHEN NEW.type='production'
BEGIN
  SELECT RAISE(ABORT, 'insufficient_credits')
  WHERE NEW.credit_cost < 1 OR NOT EXISTS (
    SELECT 1 FROM users WHERE 'user_' || id=NEW.owner_id AND status='active' AND credits>=NEW.credit_cost
  );
  INSERT INTO user_credit_ledger (id,user_id,amount,reason,task_id,actor_id,created_at)
    SELECT 'task:' || NEW.id,id,-NEW.credit_cost,'widget_task',NEW.id,NEW.owner_id,NEW.created_at
    FROM users WHERE 'user_' || id=NEW.owner_id;
END;
