CREATE TABLE IF NOT EXISTS calendar_events (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bubble_id           TEXT UNIQUE,
  company_id          UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  project_id          UUID REFERENCES projects(id) ON DELETE CASCADE,
  title               TEXT NOT NULL,
  color               TEXT DEFAULT '#417394',
  start_date          TIMESTAMPTZ,
  end_date            TIMESTAMPTZ,
  duration            INT DEFAULT 1,
  team_member_ids     TEXT[] DEFAULT '{}',
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  deleted_at          TIMESTAMPTZ
);

ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "company_isolation" ON calendar_events
  FOR ALL USING (company_id = (SELECT private.get_user_company_id()));

CREATE INDEX IF NOT EXISTS idx_calendar_events_company ON calendar_events(company_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_project ON calendar_events(project_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_dates ON calendar_events(company_id, start_date, end_date);

CREATE TRIGGER update_calendar_events_timestamp
  BEFORE UPDATE ON calendar_events FOR EACH ROW EXECUTE FUNCTION update_timestamp();
