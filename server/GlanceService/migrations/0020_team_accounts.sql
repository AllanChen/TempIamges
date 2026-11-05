-- A team is attached to a paid five-seat licence, never to five device slots.
CREATE TABLE team_members (
  user_id INTEGER PRIMARY KEY REFERENCES users(id),
  owner_id INTEGER NOT NULL REFERENCES users(id),
  source_order TEXT NOT NULL REFERENCES orders(id),
  joined_at TEXT NOT NULL,
  CHECK(user_id != owner_id)
);
CREATE INDEX team_members_owner ON team_members(owner_id);
CREATE TABLE team_invites (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL UNIQUE,
  owner_id INTEGER NOT NULL REFERENCES users(id),
  source_order TEXT NOT NULL REFERENCES orders(id),
  email TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  accepted_by INTEGER REFERENCES users(id),
  revoked_at TEXT
);
CREATE INDEX team_invites_owner ON team_invites(owner_id,expires_at);

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

