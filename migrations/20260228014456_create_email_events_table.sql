
-- SendGrid Event Webhook storage
CREATE TABLE IF NOT EXISTS email_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email           text NOT NULL,
  event           text NOT NULL,
  sg_message_id   text,
  timestamp       timestamptz NOT NULL,
  url             text,
  useragent       text,
  ip              text,
  reason          text,
  raw             jsonb,
  created_at      timestamptz DEFAULT now()
);

-- Indexes for common query patterns
CREATE INDEX idx_email_events_email ON email_events (email);
CREATE INDEX idx_email_events_event ON email_events (event);
CREATE INDEX idx_email_events_timestamp ON email_events (timestamp);
CREATE INDEX idx_email_events_sg_message_id ON email_events (sg_message_id);

-- RLS disabled — service role only via webhook
ALTER TABLE email_events ENABLE ROW LEVEL SECURITY;
-- No policies = service role only access

