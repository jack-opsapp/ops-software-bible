-- ab_config: single-row global settings
CREATE TABLE IF NOT EXISTS ab_config (
  id         integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  brand_context  text NOT NULL DEFAULT '',
  min_visitors   integer NOT NULL DEFAULT 100,
  min_days       integer NOT NULL DEFAULT 7,
  updated_at     timestamptz NOT NULL DEFAULT now()
);
INSERT INTO ab_config (id) VALUES (1) ON CONFLICT DO NOTHING;

-- ab_tests: one row per test cycle
CREATE TABLE IF NOT EXISTS ab_tests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at      timestamptz NOT NULL DEFAULT now(),
  ended_at        timestamptz,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','rotating','completed')),
  winner_variant  text CHECK (winner_variant IN ('a','b')),
  variant_a_id    uuid,
  variant_b_id    uuid,
  min_visitors    integer NOT NULL DEFAULT 100,
  min_days        integer NOT NULL DEFAULT 7
);

-- ab_variants: one row per variant config
CREATE TABLE IF NOT EXISTS ab_variants (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  test_id                 uuid REFERENCES ab_tests(id),
  slot                    text NOT NULL CHECK (slot IN ('a','b')),
  generation              integer NOT NULL DEFAULT 1,
  config                  jsonb NOT NULL DEFAULT '{}',
  ai_reasoning            text NOT NULL DEFAULT '',
  visitor_count           integer NOT NULL DEFAULT 0,
  signup_count            integer NOT NULL DEFAULT 0,
  conversion_rate         float NOT NULL DEFAULT 0,
  carried_from_variant_id uuid REFERENCES ab_variants(id)
);

-- Back-fill FK refs on ab_tests
ALTER TABLE ab_tests
  ADD CONSTRAINT fk_variant_a FOREIGN KEY (variant_a_id) REFERENCES ab_variants(id),
  ADD CONSTRAINT fk_variant_b FOREIGN KEY (variant_b_id) REFERENCES ab_variants(id);

-- ab_events: one row per tracked interaction
CREATE TABLE IF NOT EXISTS ab_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  variant_id    uuid NOT NULL REFERENCES ab_variants(id),
  session_id    text NOT NULL,
  event_type    text NOT NULL CHECK (event_type IN (
    'page_view','signup_start','signup_complete',
    'section_view','element_click','scroll_depth','app_store_click'
  )),
  section_name  text,
  element_id    text,
  dwell_ms      integer,
  value         float,
  device_type   text,
  referrer      text,
  utm_source    text,
  utm_medium    text,
  utm_campaign  text,
  timestamp     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ab_events_variant_id ON ab_events(variant_id);
CREATE INDEX IF NOT EXISTS idx_ab_events_event_type ON ab_events(event_type);
CREATE INDEX IF NOT EXISTS idx_ab_events_session_id ON ab_events(session_id);

-- RPC functions for atomic counter increments
CREATE OR REPLACE FUNCTION increment_visitor_count(variant_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE ab_variants SET visitor_count = visitor_count + 1 WHERE id = variant_id;
END;
$$;

CREATE OR REPLACE FUNCTION increment_signup_count(variant_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE ab_variants
  SET
    signup_count = signup_count + 1,
    conversion_rate = (signup_count + 1)::float / NULLIF(visitor_count, 0)
  WHERE id = variant_id;
END;
$$;
