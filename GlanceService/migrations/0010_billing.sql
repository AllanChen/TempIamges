CREATE TABLE app_users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  google_id TEXT UNIQUE,
  name TEXT,
  avatar_url TEXT,
  auth_provider TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_login_at TEXT
);

CREATE TABLE app_sessions (
  token_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES app_users(id),
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_app_sessions_user ON app_sessions(user_id);

CREATE TABLE app_oauth_states (
  state_hash TEXT PRIMARY KEY,
  expires_at TEXT NOT NULL
);
CREATE TABLE app_auth_codes (
  code_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES app_users(id),
  expires_at TEXT NOT NULL
);
CREATE TABLE app_email_codes (
  email TEXT PRIMARY KEY COLLATE NOCASE,
  code_hash TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  sent_at TEXT NOT NULL
);

CREATE TABLE wallets (
  user_id INTEGER PRIMARY KEY REFERENCES app_users(id),
  balance INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE wallet_ledger (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES app_users(id),
  delta INTEGER NOT NULL,
  reason TEXT NOT NULL,
  source_key TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);
CREATE INDEX idx_wallet_ledger_user ON wallet_ledger(user_id, created_at);

CREATE TABLE billing_orders (
  id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES app_users(id),
  sku TEXT NOT NULL,
  product_id TEXT NOT NULL,
  currency TEXT NOT NULL,
  amount TEXT NOT NULL,
  granted_credits INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','expired','completed','refunded')),
  checkout_session_id TEXT,
  checkout_expires_at TEXT,
  provider_order_id TEXT UNIQUE,
  paid_cents INTEGER,
  refunded_cents INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  completed_at TEXT,
  refunded_at TEXT
);
CREATE INDEX idx_billing_orders_user ON billing_orders(user_id, created_at DESC);
CREATE TABLE billing_webhook_events (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  order_id TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE app_entitlements (
  user_id INTEGER PRIMARY KEY REFERENCES app_users(id),
  pro_lifetime INTEGER NOT NULL DEFAULT 0,
  updates_until TEXT
);

CREATE TRIGGER app_user_created AFTER INSERT ON app_users BEGIN
  INSERT INTO wallets(user_id) VALUES(NEW.id);
  INSERT INTO app_entitlements(user_id) VALUES(NEW.id);
END;

ALTER TABLE widget_tasks ADD COLUMN credit_cost INTEGER NOT NULL DEFAULT 0;

CREATE TRIGGER billing_order_completed AFTER UPDATE OF status ON billing_orders
WHEN NEW.status='completed' AND OLD.status IN ('pending','expired')
BEGIN
  INSERT INTO wallet_ledger(id,user_id,delta,reason,source_key,created_at)
    SELECT 'grant:' || NEW.id, NEW.user_id, NEW.granted_credits, 'purchase', 'purchase:' || NEW.id, NEW.completed_at
    WHERE NEW.granted_credits > 0;
  UPDATE wallets SET balance=balance+NEW.granted_credits WHERE user_id=NEW.user_id;
  UPDATE app_entitlements SET pro_lifetime=1 WHERE user_id=NEW.user_id AND NEW.sku='pro_lifetime';
END;

CREATE TRIGGER billing_order_refunded AFTER UPDATE OF status ON billing_orders
WHEN NEW.status='refunded' AND OLD.status='completed'
BEGIN
  INSERT INTO wallet_ledger(id,user_id,delta,reason,source_key,created_at)
    SELECT 'refund:' || NEW.id, NEW.user_id, -NEW.granted_credits, 'payment_refund', 'refund:' || NEW.id, NEW.refunded_at
    WHERE NEW.granted_credits > 0;
  UPDATE wallets SET balance=balance-NEW.granted_credits WHERE user_id=NEW.user_id;
  UPDATE app_entitlements SET pro_lifetime=(SELECT COUNT(*)>0 FROM billing_orders
    WHERE user_id=NEW.user_id AND sku='pro_lifetime' AND status='completed')
    WHERE user_id=NEW.user_id AND NEW.sku='pro_lifetime';
END;

CREATE TRIGGER recalculate_updates_after_order AFTER UPDATE OF status ON billing_orders
WHEN NEW.status<>OLD.status AND NEW.sku IN ('pro_lifetime','updates_year')
BEGIN
  UPDATE app_entitlements SET updates_until=(
    WITH RECURSIVE renewals AS (
      SELECT completed_at,ROW_NUMBER() OVER (ORDER BY completed_at,id) AS n
      FROM billing_orders WHERE user_id=NEW.user_id AND sku='updates_year' AND status='completed'
    ), timeline(n,until_date) AS (
      SELECT 0,date((SELECT MIN(completed_at) FROM billing_orders
        WHERE user_id=NEW.user_id AND sku='pro_lifetime' AND status='completed'), '+1 year')
      UNION ALL
      SELECT renewals.n,date(MAX(timeline.until_date,renewals.completed_at), '+1 year')
      FROM timeline JOIN renewals ON renewals.n=timeline.n+1
    )
    SELECT until_date FROM timeline ORDER BY n DESC LIMIT 1
  ) WHERE user_id=NEW.user_id;
END;

CREATE TRIGGER charge_task_check BEFORE INSERT ON widget_tasks
WHEN NEW.type='production' AND NEW.credit_cost>0
BEGIN
  SELECT CASE WHEN COALESCE((SELECT balance FROM wallets WHERE user_id=CAST(NEW.owner_id AS INTEGER)), 0)<NEW.credit_cost
    THEN RAISE(ABORT, 'insufficient_credits') END;
END;

CREATE TRIGGER charge_task AFTER INSERT ON widget_tasks
WHEN NEW.type='production' AND NEW.credit_cost>0
BEGIN
  UPDATE wallets SET balance=balance-NEW.credit_cost WHERE user_id=CAST(NEW.owner_id AS INTEGER);
  INSERT INTO wallet_ledger(id,user_id,delta,reason,source_key,created_at)
    VALUES('charge:' || NEW.id,CAST(NEW.owner_id AS INTEGER),-NEW.credit_cost,'task','task:' || NEW.id,NEW.created_at);
END;

CREATE TRIGGER refund_task_cancel AFTER UPDATE OF status ON widget_tasks
WHEN NEW.status='cancelled' AND OLD.status='queued' AND NEW.type='production' AND NEW.credit_cost>0
BEGIN
  UPDATE wallets SET balance=balance+NEW.credit_cost WHERE user_id=CAST(NEW.owner_id AS INTEGER);
  INSERT INTO wallet_ledger(id,user_id,delta,reason,source_key,created_at)
    VALUES('task-refund:' || NEW.id,CAST(NEW.owner_id AS INTEGER),NEW.credit_cost,'task_cancel','task-refund:' || NEW.id,NEW.completed_at);
END;

CREATE TRIGGER refund_task_failure AFTER UPDATE OF status ON widget_tasks
WHEN NEW.status='failed' AND OLD.status IN ('queued','claimed','running') AND NEW.type='production' AND NEW.credit_cost>0
BEGIN
  UPDATE wallets SET balance=balance+NEW.credit_cost WHERE user_id=CAST(NEW.owner_id AS INTEGER);
  INSERT INTO wallet_ledger(id,user_id,delta,reason,source_key,created_at)
    VALUES('task-refund:' || NEW.id,CAST(NEW.owner_id AS INTEGER),NEW.credit_cost,'task_failure','task-refund:' || NEW.id,NEW.completed_at);
END;
