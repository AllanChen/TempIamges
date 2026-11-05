-- Snapshot of the latest successful claim, retained after task completion.
-- NULL means the worker did not report machine information (older clients).
ALTER TABLE widget_tasks ADD COLUMN machine_name TEXT;
ALTER TABLE widget_tasks ADD COLUMN machine_platform TEXT;
ALTER TABLE widget_tasks ADD COLUMN machine_cli_version TEXT;
