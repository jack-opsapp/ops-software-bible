
-- Lifecycle email configuration table
-- Allows admin to toggle individual lifecycle emails and adjust timing windows
CREATE TABLE IF NOT EXISTS lifecycle_email_config (
  email_type_key TEXT PRIMARY KEY,
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  min_days INT NOT NULL,
  max_days INT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by TEXT
);

-- Enable RLS (service role only — no user policies)
ALTER TABLE lifecycle_email_config ENABLE ROW LEVEL SECURITY;

-- Seed all 11 rows with current hardcoded defaults
INSERT INTO lifecycle_email_config (email_type_key, enabled, min_days, max_days) VALUES
  ('no_onboarding_day1',     TRUE, 1,  2),
  ('no_onboarding_day3',     TRUE, 3,  4),
  ('no_first_project_day2',  TRUE, 2,  3),
  ('no_first_project_day5',  TRUE, 5,  6),
  ('inactive_14d',           TRUE, 14, 15),
  ('inactive_30d',           TRUE, 30, 31),
  ('trial_expiring_7d',      TRUE, 6,  8),
  ('trial_expiring_3d',      TRUE, 2,  4),
  ('trial_expired_day1',     TRUE, 1,  2),
  ('trial_expired_day3',     TRUE, 3,  4),
  ('trial_expired_day7',     TRUE, 7,  8)
ON CONFLICT (email_type_key) DO NOTHING;

