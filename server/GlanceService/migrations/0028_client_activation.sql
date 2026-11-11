-- Unknown historical environments stay NULL and are excluded from production reports.
ALTER TABLE billing_events ADD COLUMN app_version TEXT;
ALTER TABLE billing_events ADD COLUMN app_build TEXT;
ALTER TABLE billing_events ADD COLUMN macos_version TEXT;
ALTER TABLE billing_events ADD COLUMN architecture TEXT;
ALTER TABLE billing_events ADD COLUMN language TEXT;
ALTER TABLE billing_events ADD COLUMN media_kind TEXT;
ALTER TABLE billing_events ADD COLUMN trial_started_at TEXT;
ALTER TABLE admin_pro_grants ADD COLUMN billing_mode TEXT;
ALTER TABLE widget_tasks ADD COLUMN billing_mode TEXT;
CREATE UNIQUE INDEX billing_first_preview_once ON billing_events(device_hash,billing_mode)
  WHERE kind='first_preview_success';
CREATE INDEX billing_events_environment_date ON billing_events(billing_mode,created_at,kind);

DROP TRIGGER apply_user_credit_entry;
CREATE TRIGGER apply_user_credit_entry AFTER INSERT ON user_credit_ledger
BEGIN
  UPDATE users SET credits=credits+NEW.amount,updated_at=NEW.created_at WHERE id=NEW.user_id;
  INSERT OR IGNORE INTO billing_events(id,kind,user_id,created_at,billing_mode)
  SELECT 'gift-depleted:'||COALESCE((SELECT billing_mode FROM widget_tasks WHERE id=NEW.task_id),'unknown')||':'||NEW.user_id,
    'gift_depleted',NEW.user_id,NEW.created_at,
    (SELECT billing_mode FROM widget_tasks WHERE id=NEW.task_id)
  FROM users u JOIN user_credit_ledger gift ON gift.id='signup:'||NEW.user_id
  WHERE NEW.reason='widget_task' AND u.id=NEW.user_id AND u.credits<=0 AND gift.amount>0
    AND julianday(NEW.created_at)-julianday(gift.created_at) BETWEEN 0 AND 7;
END;
