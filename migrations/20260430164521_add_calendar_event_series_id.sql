ALTER TABLE calendar_user_events
  ADD COLUMN IF NOT EXISTS series_id uuid;

CREATE INDEX IF NOT EXISTS calendar_user_events_series_id_idx
  ON calendar_user_events (series_id) WHERE series_id IS NOT NULL;
