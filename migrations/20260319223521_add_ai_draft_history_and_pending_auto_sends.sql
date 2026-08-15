
-- ══════════════════════════════════════════════════════════════════════════════
-- Sprint 5: AI Draft History + Pending Auto-Sends + Auto-Send Settings
-- ══════════════════════════════════════════════════════════════════════════════

-- 1. ai_draft_history — tracks AI-generated drafts and user edits
CREATE TABLE IF NOT EXISTS ai_draft_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id UUID NOT NULL,
  opportunity_id UUID REFERENCES opportunities(id) ON DELETE SET NULL,
  connection_id UUID REFERENCES email_connections(id) ON DELETE SET NULL,
  thread_id TEXT,
  original_draft TEXT NOT NULL,
  final_version TEXT,
  edit_distance INT DEFAULT 0,
  changes_made JSONB DEFAULT '[]'::jsonb,
  sent_without_changes BOOLEAN DEFAULT false,
  status TEXT NOT NULL DEFAULT 'drafted' CHECK (status IN ('drafted', 'sent', 'discarded')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ
);

CREATE INDEX idx_ai_draft_history_company ON ai_draft_history(company_id);
CREATE INDEX idx_ai_draft_history_user ON ai_draft_history(company_id, user_id);
CREATE INDEX idx_ai_draft_history_created ON ai_draft_history(company_id, user_id, created_at DESC);

-- RLS
ALTER TABLE ai_draft_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_draft_history_company_access"
  ON ai_draft_history FOR ALL
  USING (company_id IN (
    SELECT id FROM companies WHERE id = ai_draft_history.company_id
  ));

-- 2. pending_auto_sends — queue for auto-send emails
CREATE TABLE IF NOT EXISTS pending_auto_sends (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  connection_id UUID NOT NULL REFERENCES email_connections(id) ON DELETE CASCADE,
  opportunity_id UUID REFERENCES opportunities(id) ON DELETE SET NULL,
  thread_id TEXT NOT NULL,
  in_reply_to TEXT,
  to_emails TEXT[] NOT NULL DEFAULT '{}',
  cc_emails TEXT[] DEFAULT '{}',
  subject TEXT NOT NULL,
  draft_text TEXT NOT NULL,
  draft_history_id UUID REFERENCES ai_draft_history(id) ON DELETE SET NULL,
  scheduled_send_at TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'cancelled', 'failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  error TEXT
);

CREATE INDEX idx_pending_auto_sends_status ON pending_auto_sends(status, scheduled_send_at)
  WHERE status = 'pending';
CREATE INDEX idx_pending_auto_sends_company ON pending_auto_sends(company_id);
CREATE INDEX idx_pending_auto_sends_thread ON pending_auto_sends(thread_id);

-- RLS
ALTER TABLE pending_auto_sends ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pending_auto_sends_company_access"
  ON pending_auto_sends FOR ALL
  USING (company_id IN (
    SELECT id FROM companies WHERE id = pending_auto_sends.company_id
  ));

-- 3. Add auto_send_settings JSONB column to email_connections
ALTER TABLE email_connections
  ADD COLUMN IF NOT EXISTS auto_send_settings JSONB DEFAULT NULL;

-- COMMENT: auto_send_settings schema:
-- {
--   "enabled": boolean,
--   "business_hours_start": "08:00",
--   "business_hours_end": "18:00",
--   "timezone": "America/New_York",
--   "delay_min_minutes": 30,
--   "delay_max_minutes": 60,
--   "enabled_at": "2026-03-19T..."
-- }

