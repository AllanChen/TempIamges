-- Sandbox purchases must not grant production access or be restored by a production refund.
DROP TRIGGER fulfill_paid_order;
DROP TRIGGER revoke_refunded_order;

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
      device_limit=excluded.device_limit,tier_id=excluded.tier_id WHERE licenses.status!='active' OR (licenses.source_order IS NOT NULL AND (SELECT billing_mode FROM orders WHERE id=licenses.source_order)!=NEW.billing_mode);
  -- A paid higher tier raises the Mac limit of an active licence and becomes its source order.
  UPDATE licenses SET device_limit=NEW.device_limit,tier_id=NEW.pack_id,source_order=NEW.id,source_admin_grant=NULL,
      updates_until='9999-12-31T00:00:00.000Z'
    WHERE user_id=NEW.user_id AND status='active' AND NEW.product='pro' AND (NEW.device_limit>device_limit OR (NEW.pack_id='team' AND COALESCE(tier_id,'')!='team'));
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
  -- Fall back to the best remaining paid Pro order (most Macs, then latest).
  UPDATE licenses SET status='active',
    source_order=(SELECT id FROM orders WHERE user_id=NEW.user_id AND product='pro' AND billing_mode=NEW.billing_mode AND status IN ('paid','refund_failed') ORDER BY device_limit DESC,paid_at DESC LIMIT 1),
    purchased_at=(SELECT paid_at FROM orders WHERE user_id=NEW.user_id AND product='pro' AND billing_mode=NEW.billing_mode AND status IN ('paid','refund_failed') ORDER BY device_limit DESC,paid_at DESC LIMIT 1),
    device_limit=(SELECT device_limit FROM orders WHERE user_id=NEW.user_id AND product='pro' AND billing_mode=NEW.billing_mode AND status IN ('paid','refund_failed') ORDER BY device_limit DESC,paid_at DESC LIMIT 1),
    tier_id=(SELECT pack_id FROM orders WHERE user_id=NEW.user_id AND product='pro' AND billing_mode=NEW.billing_mode AND status IN ('paid','refund_failed') ORDER BY device_limit DESC,paid_at DESC LIMIT 1),
    updates_until='9999-12-31T00:00:00.000Z'
    WHERE user_id=NEW.user_id AND status='refunded' AND NEW.product='pro'
      AND EXISTS(SELECT 1 FROM orders WHERE user_id=NEW.user_id AND product='pro' AND billing_mode=NEW.billing_mode AND status IN ('paid','refund_failed'));
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
