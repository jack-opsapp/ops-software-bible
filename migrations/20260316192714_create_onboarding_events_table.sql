CREATE TABLE IF NOT EXISTS onboarding_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  event_type TEXT NOT NULL,
  user_id TEXT,
  variant TEXT,
  decision TEXT,
  step TEXT,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_onboarding_events_type ON onboarding_events(event_type);
CREATE INDEX idx_onboarding_events_created ON onboarding_events(created_at);
CREATE INDEX idx_onboarding_events_variant ON onboarding_events(variant);

ALTER TABLE onboarding_events ENABLE ROW LEVEL SECURITY;
