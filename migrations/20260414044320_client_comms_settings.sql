-- 059: Per-company client scheduling communications settings
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS client_comms_settings JSONB
  DEFAULT '{
    "appointment_confirmations": {"enabled": true, "delay_hours": 0},
    "day_before_reminders": {"enabled": true, "send_hour_utc": 14, "include_weather": true},
    "reschedule_requests": {"enabled": true, "min_confidence": 0.6},
    "subcontractor_coordination": {"enabled": true}
  }'::jsonb;

COMMENT ON COLUMN companies.client_comms_settings IS
  'Per-company settings for Sprint S2 client scheduling communications.';
