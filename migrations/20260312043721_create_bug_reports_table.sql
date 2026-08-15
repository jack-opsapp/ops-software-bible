
-- Bug reports table
CREATE TABLE bug_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  reporter_id UUID NOT NULL,

  description TEXT NOT NULL,
  category TEXT CHECK (category IN ('bug', 'ui_issue', 'crash', 'feature_request', 'other')) DEFAULT 'bug',

  platform TEXT NOT NULL CHECK (platform IN ('ios', 'web')),
  app_version TEXT,
  build_number TEXT,
  os_name TEXT,
  os_version TEXT,
  device_model TEXT,
  browser TEXT,
  browser_version TEXT,
  viewport_width INT,
  viewport_height INT,
  screen_name TEXT,
  url TEXT,

  network_type TEXT,
  battery_level REAL,
  free_disk_mb INT,
  free_ram_mb INT,

  console_logs JSONB DEFAULT '[]'::jsonb,
  breadcrumbs JSONB DEFAULT '[]'::jsonb,
  network_log JSONB DEFAULT '[]'::jsonb,
  state_snapshot JSONB DEFAULT '{}'::jsonb,
  custom_metadata JSONB DEFAULT '{}'::jsonb,

  screenshot_url TEXT,
  additional_attachments TEXT[] DEFAULT '{}',

  reporter_name TEXT,
  reporter_email TEXT,

  priority TEXT CHECK (priority IN ('urgent', 'high', 'medium', 'low', 'none')) DEFAULT 'none',
  status TEXT CHECK (status IN ('new', 'triaged', 'in_progress', 'resolved', 'closed', 'duplicate')) DEFAULT 'new',
  assigned_to TEXT,
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT,

  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_bug_reports_company ON bug_reports(company_id);
CREATE INDEX idx_bug_reports_status ON bug_reports(status);
CREATE INDEX idx_bug_reports_priority ON bug_reports(priority);
CREATE INDEX idx_bug_reports_reporter ON bug_reports(reporter_id);
CREATE INDEX idx_bug_reports_created ON bug_reports(created_at DESC);
CREATE INDEX idx_bug_reports_platform ON bug_reports(platform);

ALTER TABLE bug_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view bug reports for their company"
  ON bug_reports FOR SELECT
  USING (company_id IN (
    SELECT id FROM companies WHERE account_holder_id = auth.uid()::text
    UNION
    SELECT company_id FROM users WHERE id = auth.uid()
  ));

CREATE POLICY "Users can insert bug reports for their company"
  ON bug_reports FOR INSERT
  WITH CHECK (company_id IN (
    SELECT id FROM companies WHERE account_holder_id = auth.uid()::text
    UNION
    SELECT company_id FROM users WHERE id = auth.uid()
  ));

CREATE POLICY "Users can update bug reports for their company"
  ON bug_reports FOR UPDATE
  USING (company_id IN (
    SELECT id FROM companies WHERE account_holder_id = auth.uid()::text
    UNION
    SELECT company_id FROM users WHERE id = auth.uid()
  ));

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('bug-reports', 'bug-reports', false, 10485760)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Company members can upload bug report files"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'bug-reports'
    AND (auth.uid() IS NOT NULL)
  );

CREATE POLICY "Company members can read bug report files"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'bug-reports'
    AND (auth.uid() IS NOT NULL)
  );

