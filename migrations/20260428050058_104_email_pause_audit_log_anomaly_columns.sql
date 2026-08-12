ALTER TABLE public.email_pause_audit_log
  ADD COLUMN IF NOT EXISTS severity text NULL,
  ADD COLUMN IF NOT EXISTS anomaly_log_id uuid NULL;

DO $$ BEGIN
  ALTER TABLE public.email_pause_audit_log
    ADD CONSTRAINT email_pause_audit_log_severity_check
    CHECK (severity IS NULL OR severity IN ('warn', 'critical'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_email_pause_audit_log_anomaly_log_id
  ON public.email_pause_audit_log (anomaly_log_id)
  WHERE anomaly_log_id IS NOT NULL;

COMMENT ON COLUMN public.email_pause_audit_log.severity IS
  'For pause actions triggered by anomaly cron: warn | critical. NULL for manual pauses.';
COMMENT ON COLUMN public.email_pause_audit_log.anomaly_log_id IS
  'For automatic pauses, points at email_anomaly_log.id. NULL for manual pauses. FK constraint added in migration 105.';
