-- Replace the deployed positive-only guard without rewriting migration 0010.
-- Free tasks still require an active user but do not create a credit entry.
DROP TRIGGER charge_widget_task;
CREATE TRIGGER charge_widget_task AFTER INSERT ON widget_tasks
WHEN NEW.type='production'
BEGIN
  SELECT RAISE(ABORT, 'insufficient_credits')
  WHERE NEW.credit_cost < 0 OR NOT EXISTS (
    SELECT 1 FROM users WHERE 'user_' || id=NEW.owner_id AND status='active' AND credits>=NEW.credit_cost
  );
  INSERT INTO user_credit_ledger (id,user_id,amount,reason,task_id,actor_id,created_at)
    SELECT 'task:' || NEW.id,id,-NEW.credit_cost,'widget_task',NEW.id,NEW.owner_id,NEW.created_at
    FROM users WHERE 'user_' || id=NEW.owner_id AND NEW.credit_cost>0;
END;
