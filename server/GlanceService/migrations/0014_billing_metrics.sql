-- Product analytics are separate from the authoritative money ledger. No media,
-- prompt, email address or checkout token is stored in this event table.
CREATE TABLE billing_events (
  id TEXT PRIMARY KEY, kind TEXT NOT NULL, user_id INTEGER REFERENCES users(id),
  device_hash TEXT, journey_id TEXT, feature TEXT, created_at TEXT NOT NULL
);
CREATE INDEX billing_events_kind ON billing_events(kind,created_at);
CREATE INDEX billing_events_journey ON billing_events(journey_id,kind,user_id);
CREATE TABLE billing_trials (
  device_hash TEXT PRIMARY KEY, user_id INTEGER REFERENCES users(id),
  started_at TEXT NOT NULL, updated_at TEXT NOT NULL
);
ALTER TABLE orders ADD COLUMN billing_intent_id TEXT;
ALTER TABLE orders ADD COLUMN payment_method TEXT;
CREATE INDEX orders_billing_intent ON orders(user_id,billing_intent_id);
ALTER TABLE widget_tasks ADD COLUMN billing_intent_id TEXT;
ALTER TABLE widget_tasks ADD COLUMN topup_order_id TEXT;
CREATE INDEX tasks_topup_order ON widget_tasks(topup_order_id);
DROP TRIGGER apply_user_credit_entry;
CREATE TRIGGER apply_user_credit_entry AFTER INSERT ON user_credit_ledger
BEGIN
  UPDATE users SET credits=credits+NEW.amount,updated_at=NEW.created_at WHERE id=NEW.user_id;
  INSERT OR IGNORE INTO billing_events(id,kind,user_id,created_at)
  SELECT 'gift-depleted:'||NEW.user_id,'gift_depleted',NEW.user_id,NEW.created_at
  FROM users u JOIN user_credit_ledger gift ON gift.id='signup:'||NEW.user_id
  WHERE NEW.reason='widget_task' AND u.id=NEW.user_id AND u.credits<=0 AND gift.amount>0
    AND julianday(NEW.created_at)-julianday(gift.created_at) BETWEEN 0 AND 7;
END;
CREATE INDEX billing_events_user ON billing_events(user_id,kind,created_at);
CREATE TABLE billing_metrics_meta(id INTEGER PRIMARY KEY CHECK(id=1),started_at TEXT NOT NULL);
INSERT INTO billing_metrics_meta VALUES(1,strftime('%Y-%m-%dT%H:%M:%fZ','now'));

DROP TRIGGER fulfill_paid_order;
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
