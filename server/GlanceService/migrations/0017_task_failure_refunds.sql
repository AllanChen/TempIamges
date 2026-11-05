-- Delivery-aware clients acknowledge only after saving a usable result.
ALTER TABLE widget_tasks ADD COLUMN delivery_required INTEGER NOT NULL DEFAULT 0;
ALTER TABLE widget_tasks ADD COLUMN delivered_at TEXT;

-- A cancelled submission must not arrive later and charge the user. Scoped to
-- the authenticated owner; the client's persisted request key survives restart.
CREATE TABLE task_abandonments (
  owner_id TEXT NOT NULL,
  request_key TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(owner_id, request_key)
);
CREATE TRIGGER reject_abandoned_task BEFORE INSERT ON widget_tasks
WHEN NEW.request_key IS NOT NULL AND EXISTS (
  SELECT 1 FROM task_abandonments WHERE owner_id=NEW.owner_id AND request_key=NEW.request_key
)
BEGIN
  SELECT RAISE(ABORT,'request_abandoned');
END;

DROP TRIGGER refund_terminal_task;
CREATE TRIGGER refund_terminal_task AFTER UPDATE OF status ON widget_tasks
WHEN NEW.type='production' AND NEW.status IN ('failed','expired','cancelled')
BEGIN
  -- Refund the actual debit, never a mutable Widget price. The ledger key makes
  -- cancellation, timeout, repeated reports and reconciliation exactly-once.
  INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,note)
    SELECT 'refund:'||NEW.id,user_id,-amount,'task_refund','system',
      COALESCE(NEW.completed_at,strftime('%Y-%m-%dT%H:%M:%fZ','now')),NEW.id
    FROM user_credit_ledger WHERE id='task:'||NEW.id AND amount<0;
END;

-- Repair historical terminal failures/cancellations that retained a debit.
-- Successful tasks are intentionally not inferred to have failed.
INSERT OR IGNORE INTO user_credit_ledger(id,user_id,amount,reason,actor_id,created_at,note)
  SELECT 'refund:'||t.id,l.user_id,-l.amount,'task_refund','system',
    strftime('%Y-%m-%dT%H:%M:%fZ','now'),t.id
  FROM widget_tasks t JOIN user_credit_ledger l ON l.id='task:'||t.id
  WHERE t.type='production' AND t.status IN ('failed','expired','cancelled') AND l.amount<0;
