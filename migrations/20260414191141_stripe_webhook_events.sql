CREATE TABLE IF NOT EXISTS stripe_webhook_events (
  event_id     TEXT PRIMARY KEY,
  event_type   TEXT NOT NULL,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_received_at
  ON stripe_webhook_events (received_at DESC);

COMMENT ON TABLE stripe_webhook_events IS
  'Dedup log for Stripe webhook deliveries. Insert before processing; skip if PK conflict.';
