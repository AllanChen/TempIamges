-- Admin grants are audited separately from paid orders and never create revenue.
-- Keep paid-order fulfillment/refund triggers intact while allowing a grant source.
DROP TRIGGER fulfill_paid_order;
DROP TRIGGER revoke_refunded_order;
CREATE TABLE admin_pro_grants (
  id TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id),
  note TEXT NOT NULL, actor_id TEXT NOT NULL, created_at TEXT NOT NULL,
  updates_months INTEGER NOT NULL CHECK(updates_months BETWEEN 1 AND 120)
);
CREATE INDEX admin_pro_grants_user ON admin_pro_grants(user_id,created_at);
CREATE TABLE licenses_with_grants (
  user_id INTEGER PRIMARY KEY REFERENCES users(id), status TEXT NOT NULL,
  purchased_at TEXT NOT NULL, updates_until TEXT NOT NULL,
  source_order TEXT REFERENCES orders(id), source_admin_grant TEXT REFERENCES admin_pro_grants(id)
);
INSERT INTO licenses_with_grants(user_id,status,purchased_at,updates_until,source_order)
  SELECT user_id,status,purchased_at,updates_until,source_order FROM licenses;
DROP TABLE licenses;
ALTER TABLE licenses_with_grants RENAME TO licenses;
CREATE TRIGGER apply_admin_pro_grant AFTER INSERT ON admin_pro_grants
BEGIN
  SELECT RAISE(ABORT,'account_disabled') WHERE NOT EXISTS(
    SELECT 1 FROM users WHERE id=NEW.user_id AND status='active');
  SELECT RAISE(ABORT,'already_pro') WHERE EXISTS(
    SELECT 1 FROM licenses WHERE user_id=NEW.user_id AND status='active');
  INSERT INTO licenses(user_id,status,purchased_at,updates_until,source_order,source_admin_grant)
    VALUES(NEW.user_id,'active',NEW.created_at,
      strftime('%Y-%m-%dT%H:%M:%fZ',NEW.created_at,'+'||NEW.updates_months||' months'),NULL,NEW.id)
    ON CONFLICT(user_id) DO UPDATE SET status='active',purchased_at=excluded.purchased_at,
      updates_until=excluded.updates_until,source_order=NULL,source_admin_grant=excluded.source_admin_grant;
  UPDATE users SET trial_voided=1,updated_at=NEW.created_at WHERE id=NEW.user_id;
END;

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
