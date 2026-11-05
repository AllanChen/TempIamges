-- Preserve order IDs, references and fulfillment triggers while adding currencies.
-- All pre-launch orders were sandbox orders. New orders snapshot their environment.
PRAGMA defer_foreign_keys=ON;

DROP TRIGGER revoke_refunded_order;

DROP TRIGGER fulfill_paid_order;

CREATE TABLE orders_multicurrency (
  id TEXT PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id),
  product TEXT NOT NULL CHECK(product IN ('pro','renewal','credits')), pack_id TEXT,
  currency TEXT NOT NULL CHECK(currency IN ('CNY','USD','JPY','EUR','HKD')), amount INTEGER NOT NULL CHECK(amount>0),
  credits INTEGER NOT NULL DEFAULT 0, bonus_credits INTEGER NOT NULL DEFAULT 0,
  product_id TEXT NOT NULL, tax_category TEXT NOT NULL, tax_included INTEGER NOT NULL,
  updates_months INTEGER NOT NULL DEFAULT 12,
  status TEXT NOT NULL DEFAULT 'pending', request_key TEXT NOT NULL, request_hash TEXT NOT NULL,
  checkout_url TEXT, checkout_session_id TEXT, checkout_expires_at TEXT NOT NULL,
  provider_order_id TEXT UNIQUE, provider_payment_id TEXT, paid_amount INTEGER,language TEXT NOT NULL DEFAULT 'en',
  refunded_amount INTEGER NOT NULL DEFAULT 0, previous_updates_until TEXT,
  refund_reason TEXT, refund_status TEXT, refund_ticket_id TEXT,
  created_at TEXT NOT NULL, paid_at TEXT, refunded_at TEXT, billing_intent_id TEXT, payment_method TEXT, device_limit INTEGER NOT NULL DEFAULT 2,
  billing_mode TEXT NOT NULL DEFAULT 'test' CHECK(billing_mode IN ('test','prod')),
  UNIQUE(user_id,request_key)
);

INSERT INTO orders_multicurrency(id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,updates_months,status,request_key,request_hash,checkout_url,checkout_session_id,checkout_expires_at,provider_order_id,provider_payment_id,paid_amount,language,refunded_amount,previous_updates_until,refund_reason,refund_status,refund_ticket_id,created_at,paid_at,refunded_at,billing_intent_id,payment_method,device_limit) SELECT id,user_id,product,pack_id,currency,amount,credits,bonus_credits,product_id,tax_category,tax_included,updates_months,status,request_key,request_hash,checkout_url,checkout_session_id,checkout_expires_at,provider_order_id,provider_payment_id,paid_amount,language,refunded_amount,previous_updates_until,refund_reason,refund_status,refund_ticket_id,created_at,paid_at,refunded_at,billing_intent_id,payment_method,device_limit FROM orders;

DROP TABLE orders;

ALTER TABLE orders_multicurrency RENAME TO orders;

CREATE UNIQUE INDEX one_pending_product ON orders(user_id,product,COALESCE(pack_id,'')) WHERE status='pending';

CREATE INDEX orders_user ON orders(user_id,created_at);

CREATE INDEX orders_billing_intent ON orders(user_id,billing_intent_id);

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
  -- Fall back to the best remaining paid Pro order (most Macs, then latest).
  UPDATE licenses SET status='active',
    source_order=(SELECT id FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed') ORDER BY device_limit DESC,paid_at DESC LIMIT 1),
    purchased_at=(SELECT paid_at FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed') ORDER BY device_limit DESC,paid_at DESC LIMIT 1),
    device_limit=(SELECT device_limit FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed') ORDER BY device_limit DESC,paid_at DESC LIMIT 1),
    tier_id=(SELECT pack_id FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed') ORDER BY device_limit DESC,paid_at DESC LIMIT 1),
    updates_until='9999-12-31T00:00:00.000Z'
    WHERE user_id=NEW.user_id AND status='refunded' AND NEW.product='pro'
      AND EXISTS(SELECT 1 FROM orders WHERE user_id=NEW.user_id AND product='pro' AND status IN ('paid','refund_failed'));
  -- Refunding a paid tier that is not the source (an older, smaller order after
  -- an upgrade) leaves the licence as it is; refunding the source may lower the
  -- Mac limit, so surplus Macs are released below.
  UPDATE license_devices SET released_at=NEW.refunded_at WHERE user_id=NEW.user_id AND released_at IS NULL
    AND NEW.product='pro' AND EXISTS(SELECT 1 FROM licenses WHERE user_id=NEW.user_id AND source_order=NEW.id AND status='refunded');
  UPDATE license_devices SET released_at=NEW.refunded_at WHERE NEW.product='pro' AND released_at IS NULL AND user_id=NEW.user_id
    AND id IN (SELECT id FROM license_devices d WHERE d.user_id=NEW.user_id AND d.released_at IS NULL ORDER BY d.activated_at DESC
      LIMIT MAX(0,(SELECT COUNT(*) FROM license_devices WHERE user_id=NEW.user_id AND released_at IS NULL)
        -(SELECT device_limit FROM licenses WHERE user_id=NEW.user_id AND status='active')));
  UPDATE refund_requests SET status='refunded',updated_at=NEW.refunded_at WHERE order_id=NEW.id;
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
  -- A first purchase (or a purchase after a refund) activates the licence with
  -- the paid tier. No CASE expressions here: the migration splitter would take
  -- their END for the trigger's END.
  INSERT INTO licenses(user_id,status,purchased_at,updates_until,source_order,device_limit,tier_id)
    SELECT NEW.user_id,'active',NEW.paid_at,'9999-12-31T00:00:00.000Z',NEW.id,NEW.device_limit,NEW.pack_id
    WHERE NEW.product='pro'
    ON CONFLICT(user_id) DO UPDATE SET status='active',purchased_at=excluded.purchased_at,
      updates_until=excluded.updates_until,source_order=excluded.source_order,source_admin_grant=NULL,
      device_limit=excluded.device_limit,tier_id=excluded.tier_id WHERE licenses.status!='active';
  -- A paid higher tier raises the Mac limit of an active licence and becomes its source order.
  UPDATE licenses SET device_limit=NEW.device_limit,tier_id=NEW.pack_id,source_order=NEW.id,source_admin_grant=NULL,
      updates_until='9999-12-31T00:00:00.000Z'
    WHERE user_id=NEW.user_id AND status='active' AND NEW.product='pro' AND (NEW.device_limit>device_limit OR (NEW.pack_id='team' AND COALESCE(tier_id,'')!='team'));
  UPDATE users SET trial_voided=1 WHERE id=NEW.user_id AND NEW.product='pro';
END;

PRAGMA defer_foreign_keys=OFF;
