CREATE TABLE account_deletions (
  user_id INTEGER PRIMARY KEY REFERENCES users(id),
  requested_at TEXT NOT NULL,
  purge_after TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  last_attempt_at TEXT,
  completed_at TEXT
);
