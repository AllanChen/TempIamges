-- User-facing failure category reported by the worker, e.g. the provider's
-- safety review (error_code 'content_rejected': sexual / political / other).
-- Allow-listed by the service; never free provider or traceback text.
ALTER TABLE widget_tasks ADD COLUMN error_reason TEXT;
