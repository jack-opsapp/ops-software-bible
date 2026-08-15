-- 060: Schedule confirmation state + expanded client comms settings

ALTER TABLE project_tasks
  ADD COLUMN IF NOT EXISTS schedule_confirmed_at TIMESTAMPTZ;

ALTER TABLE project_tasks
  ADD COLUMN IF NOT EXISTS schedule_confirmed_by UUID;

COMMENT ON COLUMN project_tasks.schedule_confirmed_at IS
  'When the task was explicitly or automatically marked as schedule-confirmed.';

COMMENT ON COLUMN project_tasks.schedule_confirmed_by IS
  'User id who confirmed the schedule. NULL when auto-confirmed by cron.';

CREATE INDEX IF NOT EXISTS idx_project_tasks_schedule_confirmed_at
  ON project_tasks(schedule_confirmed_at)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_project_tasks_auto_confirm_candidates
  ON project_tasks(company_id, updated_at)
  WHERE schedule_confirmed_at IS NULL
    AND start_date IS NOT NULL
    AND deleted_at IS NULL;

ALTER TABLE agent_actions
  ADD COLUMN IF NOT EXISTS auto_execute_at TIMESTAMPTZ;

COMMENT ON COLUMN agent_actions.auto_execute_at IS
  'If set, the action is automatically approved and executed at this time unless the user rejects or cancels first.';

CREATE INDEX IF NOT EXISTS idx_agent_actions_auto_execute
  ON agent_actions(auto_execute_at)
  WHERE status = 'pending' AND auto_execute_at IS NOT NULL;

ALTER TABLE companies
  ALTER COLUMN client_comms_settings SET DEFAULT '{
    "comms_wizard_completed_at": null,
    "comms_wizard_version": 0,
    "appointment_confirmation": {
      "level": "draft_on_confirm",
      "confirm_mode": "explicit",
      "auto_confirm_after_hours": 4,
      "send_delay_minutes": 15,
      "reschedule_behavior": "draft"
    },
    "appointment_reminder": {
      "enabled": true,
      "lead_days": 1,
      "send_hour_local": 14,
      "include_weather": true,
      "autonomy": "draft_to_queue",
      "send_delay_minutes": 15
    },
    "status_update": {
      "cadence": "off",
      "weekly_day": 1,
      "autonomy": "draft_to_queue",
      "send_delay_minutes": 15
    },
    "payment_reminder": {
      "enabled": true,
      "preset": "standard",
      "custom_days": [7, 14, 30, 45],
      "max_reminders": 4,
      "autonomy": "draft_to_queue",
      "send_delay_minutes": 15
    },
    "invoice_cover": {
      "enabled": true,
      "threshold": 0,
      "autonomy": "draft_to_queue",
      "send_delay_minutes": 15
    },
    "reschedule_request": {
      "enabled": true,
      "behavior": "detect_and_draft",
      "min_confidence": 0.6,
      "autonomy": "draft_to_queue",
      "send_delay_minutes": 15
    },
    "subcontractor_coordination": {
      "enabled": false,
      "trigger": "manual"
    },
    "appointment_confirmations": {
      "enabled": true,
      "delay_hours": 0
    },
    "day_before_reminders": {
      "enabled": true,
      "send_hour_utc": 14,
      "include_weather": true
    },
    "reschedule_requests": {
      "enabled": true,
      "min_confidence": 0.6
    }
  }'::jsonb;

COMMENT ON COLUMN companies.client_comms_settings IS
  'Per-company communication settings. New wizard-driven schema (060): appointment_confirmation (5-level autonomy), appointment_reminder (configurable lead_days), status_update, payment_reminder, invoice_cover, reschedule_request, subcontractor_coordination. Legacy keys retained for backwards compat.';
