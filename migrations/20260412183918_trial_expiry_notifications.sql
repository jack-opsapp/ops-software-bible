CREATE TABLE IF NOT EXISTS trial_expiry_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  notification_type text NOT NULL CHECK (notification_type IN (
    'warning_7d',
    'warning_5d',
    'discount_3d',
    'warning_1d',
    'reengagement_7d',
    'reengagement_30d'
  )),
  sent_at timestamptz NOT NULL DEFAULT now(),
  promo_code_50 text,
  promo_code_30 text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT trial_expiry_notifications_unique UNIQUE (company_id, notification_type)
);

CREATE INDEX IF NOT EXISTS idx_trial_expiry_notifications_company
  ON trial_expiry_notifications (company_id);

CREATE INDEX IF NOT EXISTS idx_trial_expiry_notifications_sent_at
  ON trial_expiry_notifications (sent_at DESC);
