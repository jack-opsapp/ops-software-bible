CREATE TABLE app_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id),
  company_id UUID,
  event_type TEXT NOT NULL CHECK (event_type IN (
    'page_view', 'feature_use', 'element_click', 'modal_open', 'modal_close',
    'widget_interact', 'navigation', 'action_complete'
  )),
  page_name TEXT,
  feature_name TEXT,
  element_id TEXT,
  dwell_ms INTEGER,
  device_type TEXT,
  metadata JSONB DEFAULT '{}',
  timestamp TIMESTAMPTZ DEFAULT now() NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX idx_app_events_session ON app_events(session_id);
CREATE INDEX idx_app_events_timestamp ON app_events(timestamp);
CREATE INDEX idx_app_events_type_page ON app_events(event_type, page_name);
CREATE INDEX idx_app_events_company ON app_events(company_id);

ALTER TABLE app_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admin read access" ON app_events
  FOR SELECT USING (auth.jwt() ->> 'role' = 'admin');
