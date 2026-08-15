
-- Email log table to track all lifecycle emails sent
CREATE TABLE email_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  email_type text NOT NULL,
  recipient_email text NOT NULL,
  subject text,
  sent_at timestamptz DEFAULT now(),
  status text DEFAULT 'sent', -- 'sent', 'failed', 'opened', 'clicked'
  error_message text,
  metadata jsonb DEFAULT '{}',
  
  -- Prevent duplicate sends of same email type to same user
  UNIQUE(user_id, email_type)
);

-- Index for quick lookups
CREATE INDEX idx_email_log_user_id ON email_log(user_id);
CREATE INDEX idx_email_log_email_type ON email_log(email_type);
CREATE INDEX idx_email_log_sent_at ON email_log(sent_at DESC);

-- RLS policies
ALTER TABLE email_log ENABLE ROW LEVEL SECURITY;

-- Admins can view all email logs (check by email from JWT)
CREATE POLICY "Admins can view all email logs"
  ON email_log FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM admins 
      WHERE admins.email = auth.jwt() ->> 'email'
    )
  );

-- Service role can insert (for edge function)
CREATE POLICY "Service role can insert email logs"
  ON email_log FOR INSERT
  WITH CHECK (true);

-- Comments for the admin dashboard agent
COMMENT ON TABLE email_log IS 'Tracks all lifecycle/re-engagement emails sent to users';
COMMENT ON COLUMN email_log.email_type IS 'Email types: no_onboarding_day1, no_onboarding_day3, no_first_project_day2, no_first_project_day5, inactive_14d, inactive_30d, trial_expiring_7d, trial_expiring_3d, trial_expired_day1, trial_expired_day3, trial_expired_day7';
COMMENT ON COLUMN email_log.status IS 'Status: sent, failed, opened, clicked';
COMMENT ON COLUMN email_log.metadata IS 'Additional data like company_name, first_name for reference';

