
-- Junction table: links opportunities to email thread IDs
CREATE TABLE opportunity_email_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  opportunity_id UUID NOT NULL REFERENCES opportunities(id) ON DELETE CASCADE,
  thread_id TEXT NOT NULL,
  connection_id UUID REFERENCES email_connections(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(thread_id, connection_id)
);

CREATE INDEX idx_oet_thread ON opportunity_email_threads(thread_id);
CREATE INDEX idx_oet_opportunity ON opportunity_email_threads(opportunity_id);

ALTER TABLE opportunity_email_threads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Company-scoped thread access" ON opportunity_email_threads
  FOR ALL USING (
    opportunity_id IN (
      SELECT id FROM opportunities WHERE company_id = (auth.jwt()->>'company_id')::uuid
    )
  );

-- Admin feature overrides (OPS admin controls per-company AI features)
CREATE TABLE admin_feature_overrides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id TEXT NOT NULL,
  feature_key TEXT NOT NULL,
  enabled BOOLEAN NOT NULL DEFAULT false,
  enabled_by TEXT,
  enabled_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}',
  UNIQUE(company_id, feature_key)
);

ALTER TABLE admin_feature_overrides ENABLE ROW LEVEL SECURITY;

