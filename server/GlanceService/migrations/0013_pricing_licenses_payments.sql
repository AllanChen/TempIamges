-- Existing accounts, sessions and ledger IDs are preserved. Defer parent-key
-- checks while replacing the positive-only balance constraint.
PRAGMA defer_foreign_keys = ON;
DROP TRIGGER charge_widget_task;
DROP TRIGGER apply_user_credit_entry;
CREATE TABLE users_billing (
  id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT NOT NULL UNIQUE,
  google_id TEXT UNIQUE, name TEXT, avatar_url TEXT, auth_provider TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  credits INTEGER NOT NULL DEFAULT 0 CHECK (credits BETWEEN -1000000000 AND 1000000000),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL, last_login_at TEXT,
  trial_started_at TEXT, trial_voided INTEGER NOT NULL DEFAULT 0, widget_notice_seen INTEGER NOT NULL DEFAULT 0
);
INSERT INTO users_billing(id,email,google_id,name,avatar_url,auth_provider,status,credits,created_at,updated_at,last_login_at)
  SELECT id,email,google_id,name,avatar_url,auth_provider,status,credits,created_at,updated_at,last_login_at FROM users;
DROP TABLE users;
ALTER TABLE users_billing RENAME TO users;
ALTER TABLE user_oauth_states ADD COLUMN device_hash TEXT;
ALTER TABLE user_auth_codes ADD COLUMN device_hash TEXT;
ALTER TABLE user_credit_ledger ADD COLUMN order_id TEXT;
ALTER TABLE user_credit_ledger ADD COLUMN note TEXT;
CREATE TABLE signup_devices (device_hash TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), created_at TEXT NOT NULL);
CREATE TABLE billing_settings (id INTEGER PRIMARY KEY CHECK(id=1), revision INTEGER NOT NULL, json TEXT NOT NULL, updated_at TEXT NOT NULL);
CREATE TABLE orders (
  id TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id),
  product TEXT NOT NULL CHECK(product IN ('pro','renewal','credits')), pack_id TEXT,
  currency TEXT NOT NULL CHECK(currency IN ('CNY','USD')), amount INTEGER NOT NULL CHECK(amount>0),
  credits INTEGER NOT NULL DEFAULT 0, bonus_credits INTEGER NOT NULL DEFAULT 0,
  product_id TEXT NOT NULL, tax_category TEXT NOT NULL, tax_included INTEGER NOT NULL,
  updates_months INTEGER NOT NULL DEFAULT 12,
  status TEXT NOT NULL DEFAULT 'pending', request_key TEXT NOT NULL, request_hash TEXT NOT NULL,
  checkout_url TEXT, checkout_session_id TEXT, checkout_expires_at TEXT NOT NULL,
  provider_order_id TEXT UNIQUE, provider_payment_id TEXT, paid_amount INTEGER,language TEXT NOT NULL DEFAULT 'en',
  refunded_amount INTEGER NOT NULL DEFAULT 0, previous_updates_until TEXT,
  refund_reason TEXT, refund_status TEXT, refund_ticket_id TEXT,
  created_at TEXT NOT NULL, paid_at TEXT, refunded_at TEXT,
  UNIQUE(user_id,request_key)
);
CREATE UNIQUE INDEX one_pending_product ON orders(user_id,product,COALESCE(pack_id,'')) WHERE status='pending';
CREATE INDEX orders_user ON orders(user_id,created_at);
CREATE TABLE billing_webhook_events (id TEXT PRIMARY KEY, event_type TEXT NOT NULL, business_id TEXT NOT NULL, order_id TEXT NOT NULL REFERENCES orders(id), created_at TEXT NOT NULL);
CREATE UNIQUE INDEX webhook_business_event ON billing_webhook_events(event_type,business_id);
CREATE TABLE licenses (
  user_id INTEGER PRIMARY KEY REFERENCES users(id), status TEXT NOT NULL,
  purchased_at TEXT NOT NULL, updates_until TEXT NOT NULL,
  source_order TEXT NOT NULL REFERENCES orders(id)
);
CREATE TABLE license_devices (
  id TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), device_hash TEXT NOT NULL,
  name TEXT NOT NULL, activated_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, released_at TEXT,
  UNIQUE(user_id,device_hash)
);
CREATE TABLE device_releases (id TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id), device_id TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE refund_requests (
  id TEXT PRIMARY KEY, order_id TEXT NOT NULL REFERENCES orders(id), user_id INTEGER NOT NULL REFERENCES users(id),
  reason TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'requested', created_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX one_open_refund ON refund_requests(order_id) WHERE status IN ('requested','processing');

-- Accounting remains ledger-driven. A task's debit and terminal refund execute
-- in the same SQL statement as its state change, including worker races.
CREATE TRIGGER apply_user_credit_entry AFTER INSERT ON user_credit_ledger
BEGIN
  UPDATE users SET credits=credits+NEW.amount,updated_at=NEW.created_at WHERE id=NEW.user_id;
END;

CREATE TRIGGER charge_widget_task AFTER INSERT ON widget_tasks WHEN NEW.type='production'
BEGIN
  SELECT RAISE(ABORT,'insufficient_credits') WHERE NEW.credit_cost<0 OR NOT EXISTS (
    SELECT 1 FROM users WHERE 'user_'||id=NEW.owner_id AND status='active'
      AND (NEW.credit_cost=0 OR credits>=NEW.credit_cost)
  );
  INSERT INTO user_credit_ledger(id,user_id,amount,reason,task_id,actor_id,created_at)
    SELECT 'task:'||NEW.id,id,-NEW.credit_cost,'widget_task',NEW.id,NEW.owner_id,NEW.created_at
    FROM users WHERE 'user_'||id=NEW.owner_id AND NEW.credit_cost>0;
END;
-- The original task_id uniqueness is deliberately retained on debit rows.
-- Refunds use the unique ledger primary key and do not duplicate that column.
CREATE TRIGGER refund_terminal_task AFTER UPDATE OF status ON widget_tasks
WHEN NEW.type='production' AND NEW.credit_cost>0 AND OLD.status IN ('queued','claimed','running')
  AND (NEW.status IN ('failed','expired') OR (NEW.status='cancelled' AND OLD.status='queued'))
BEGIN
  INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,note)
    SELECT 'refund:'||NEW.id,id,NEW.credit_cost,'task_refund','system',NEW.completed_at,NEW.id
    FROM users WHERE 'user_'||id=NEW.owner_id;
END;

-- Webhook event persistence and the order transition are batched atomically.
-- All fulfillment is triggered by the first paid transition, not by a callback.
CREATE TRIGGER fulfill_paid_order AFTER UPDATE OF status ON orders
WHEN NEW.status='paid' AND OLD.status IN ('pending','expired','abandoned')
BEGIN
  INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,order_id)
    SELECT 'order:'||NEW.id,NEW.user_id,NEW.credits,'purchase_credits','payment',NEW.paid_at,NEW.id
    WHERE NEW.product='credits' AND NEW.credits>0;
  INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,order_id)
    SELECT 'pro-bonus:'||NEW.user_id,NEW.user_id,NEW.bonus_credits,'pro_bonus','payment',NEW.paid_at,NEW.id
    WHERE NEW.product='pro' AND NEW.bonus_credits>0;
  UPDATE orders SET bonus_credits=0 WHERE id=NEW.id AND NEW.product='pro'
    AND NOT EXISTS(SELECT 1 FROM user_credit_ledger WHERE id='pro-bonus:'||NEW.user_id AND order_id=NEW.id);
  INSERT INTO licenses(user_id,status,purchased_at,updates_until,source_order)
    SELECT NEW.user_id,'active',NEW.paid_at,strftime('%Y-%m-%dT%H:%M:%fZ',NEW.paid_at,'+'||NEW.updates_months||' months'),NEW.id
    WHERE NEW.product='pro'
    ON CONFLICT(user_id) DO UPDATE SET status='active',purchased_at=excluded.purchased_at,
      updates_until=excluded.updates_until,source_order=excluded.source_order WHERE licenses.status!='active';
  UPDATE licenses SET updates_until=strftime('%Y-%m-%dT%H:%M:%fZ',NEW.paid_at,'+'||NEW.updates_months||' months')
    WHERE user_id=NEW.user_id AND status='active' AND NEW.product='renewal';
  UPDATE users SET trial_voided=1 WHERE id=NEW.user_id AND NEW.product='pro';
END;
CREATE TRIGGER revoke_refunded_order AFTER UPDATE OF status ON orders
WHEN NEW.status='refunded' AND OLD.status IN ('paid','refund_failed')
BEGIN
  INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,order_id)
    SELECT 'refund-order:'||NEW.id,NEW.user_id,-NEW.credits,'order_refund','payment',NEW.refunded_at,NEW.id
    WHERE NEW.product='credits';
  INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,order_id)
    SELECT 'refund-order:'||NEW.id,NEW.user_id,-amount,'order_refund','payment',NEW.refunded_at,NEW.id
    FROM user_credit_ledger WHERE id='pro-bonus:'||NEW.user_id AND order_id=NEW.id AND NEW.product='pro';
  UPDATE licenses SET status='refunded' WHERE user_id=NEW.user_id AND source_order=NEW.id AND NEW.product='pro';
  UPDATE licenses SET status='active',
    source_order=(SELECT id FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed') ORDER BY paid_at DESC LIMIT 1),
    purchased_at=(SELECT paid_at FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed') ORDER BY paid_at DESC LIMIT 1),
    updates_until=(SELECT strftime('%Y-%m-%dT%H:%M:%fZ',paid_at,'+'||updates_months||' months') FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed') ORDER BY paid_at DESC LIMIT 1)
    WHERE user_id=NEW.user_id AND status='refunded' AND NEW.product='pro'
      AND EXISTS(SELECT 1 FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed'));
  UPDATE orders SET previous_updates_until=NEW.previous_updates_until
    WHERE user_id=NEW.user_id AND product='renewal' AND id!=NEW.id AND NEW.product='renewal'
      AND previous_updates_until=strftime('%Y-%m-%dT%H:%M:%fZ',NEW.paid_at,'+'||NEW.updates_months||' months');
  UPDATE license_devices SET released_at=NEW.refunded_at WHERE user_id=NEW.user_id AND released_at IS NULL
    AND NEW.product='pro' AND EXISTS(SELECT 1 FROM licenses WHERE user_id=NEW.user_id AND source_order=NEW.id AND status='refunded');
  UPDATE licenses SET updates_until=NEW.previous_updates_until
    WHERE user_id=NEW.user_id AND NEW.product='renewal'
      AND updates_until=strftime('%Y-%m-%dT%H:%M:%fZ',NEW.paid_at,'+'||NEW.updates_months||' months');
  UPDATE refund_requests SET status='refunded',updated_at=NEW.refunded_at WHERE order_id=NEW.id;
END;

-- DROP TABLE users leaves SQLite's deferred violation counter set even after
-- the replacement is renamed back to users. Validate the resolved references
-- now, then clear that counter before D1 commits the migration.
PRAGMA defer_foreign_keys = OFF;
