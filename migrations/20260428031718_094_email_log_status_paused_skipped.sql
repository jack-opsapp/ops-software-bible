COMMENT ON COLUMN public.email_log.status IS
  'Canonical values: sent | suppression_skipped | paused_skipped | failed. paused_skipped: gatedSend short-circuited because email_pause_state had a matching active scope. suppression_skipped: gatedSend short-circuited because email_suppressions had a matching row. failed: SendGrid returned an error after sending was attempted.';
