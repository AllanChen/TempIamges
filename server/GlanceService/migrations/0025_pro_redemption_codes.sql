CREATE TABLE pro_redemption_codes (
  id TEXT PRIMARY KEY,
  batch_id TEXT NOT NULL,
  code_hash TEXT NOT NULL UNIQUE,
  code_hint TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('lifetime','one_year')),
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','revoked')),
  note TEXT NOT NULL,
  actor_id TEXT NOT NULL,
  device_limit INTEGER NOT NULL CHECK(device_limit BETWEEN 1 AND 20),
  billing_mode TEXT NOT NULL CHECK(billing_mode IN ('test','prod')),
  expires_at TEXT,
  redeemed_by INTEGER REFERENCES users(id),
  redeemed_at TEXT,
  access_expires_at TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX pro_redemption_codes_batch ON pro_redemption_codes(batch_id,created_at);
CREATE INDEX pro_redemption_codes_redeemed_by ON pro_redemption_codes(redeemed_by,redeemed_at);
CREATE INDEX pro_redemption_codes_expiry ON pro_redemption_codes(access_expires_at,status);

ALTER TABLE licenses ADD COLUMN source_redemption_code TEXT REFERENCES pro_redemption_codes(id);
ALTER TABLE licenses ADD COLUMN access_expires_at TEXT;
CREATE INDEX licenses_redemption_expiry ON licenses(access_expires_at,status);
CREATE INDEX licenses_redemption_source ON licenses(source_redemption_code);

DROP TRIGGER apply_admin_pro_grant;
DROP TRIGGER fulfill_paid_order;

CREATE TRIGGER apply_admin_pro_grant AFTER INSERT ON admin_pro_grants
BEGIN
  SELECT RAISE(ABORT,'account_disabled') WHERE NOT EXISTS(
    SELECT 1 FROM users WHERE id=NEW.user_id AND status='active');
  SELECT RAISE(ABORT,'already_pro') WHERE EXISTS(
    SELECT 1 FROM licenses WHERE user_id=NEW.user_id AND status='active');
  INSERT INTO licenses(user_id,status,purchased_at,updates_until,source_order,source_admin_grant,device_limit,tier_id)
    VALUES(NEW.user_id,'active',NEW.created_at,'9999-12-31T00:00:00.000Z',NULL,NEW.id,NEW.device_limit,NULL)
    ON CONFLICT(user_id) DO UPDATE SET status='active',purchased_at=excluded.purchased_at,
      updates_until=excluded.updates_until,source_order=NULL,source_admin_grant=excluded.source_admin_grant,
      source_redemption_code=NULL,access_expires_at=NULL,device_limit=excluded.device_limit,tier_id=NULL;
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
  INSERT INTO licenses(user_id,status,purchased_at,updates_until,source_order,device_limit,tier_id)
    SELECT NEW.user_id,'active',NEW.paid_at,'9999-12-31T00:00:00.000Z',NEW.id,NEW.device_limit,NEW.pack_id
    WHERE NEW.product='pro'
    ON CONFLICT(user_id) DO UPDATE SET status='active',purchased_at=excluded.purchased_at,
      updates_until=excluded.updates_until,source_order=excluded.source_order,source_admin_grant=NULL,
      source_redemption_code=NULL,access_expires_at=NULL,device_limit=excluded.device_limit,tier_id=excluded.tier_id
      WHERE licenses.status!='active' OR (licenses.source_order IS NOT NULL AND (SELECT billing_mode FROM orders WHERE id=licenses.source_order)!=NEW.billing_mode);
  UPDATE licenses SET device_limit=NEW.device_limit,tier_id=NEW.pack_id,source_order=NEW.id,source_admin_grant=NULL,
      source_redemption_code=NULL,access_expires_at=NULL,updates_until='9999-12-31T00:00:00.000Z'
    WHERE user_id=NEW.user_id AND status='active' AND NEW.product='pro' AND (NEW.device_limit>device_limit OR (NEW.pack_id='team' AND COALESCE(tier_id,'')!='team'));
  UPDATE users SET trial_voided=1 WHERE id=NEW.user_id AND NEW.product='pro';
END;
