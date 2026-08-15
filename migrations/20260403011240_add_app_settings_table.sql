
-- Simple key-value settings table for feature flags and config
CREATE TABLE IF NOT EXISTS app_settings (
  key text PRIMARY KEY,
  value jsonb NOT NULL DEFAULT 'true'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Blog newsletter starts DISABLED so Jackson can test first
INSERT INTO app_settings (key, value) VALUES ('blog_newsletter_enabled', 'false'::jsonb)
ON CONFLICT (key) DO NOTHING;

COMMENT ON TABLE app_settings IS 'Simple key-value store for feature flags and app configuration';

