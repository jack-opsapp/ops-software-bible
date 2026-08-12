CREATE INDEX IF NOT EXISTS idx_email_events_timestamp_event
  ON public.email_events (timestamp DESC, event);

ANALYZE public.email_events;
