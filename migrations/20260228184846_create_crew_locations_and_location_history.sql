-- Current crew positions (one row per member, upserted)
CREATE TABLE IF NOT EXISTS crew_locations (
    user_id UUID PRIMARY KEY,
    org_id UUID NOT NULL,
    first_name TEXT NOT NULL DEFAULT '',
    last_name TEXT,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    battery_level REAL,
    is_background BOOLEAN DEFAULT false,
    current_task_name TEXT,
    current_project_name TEXT,
    current_project_id TEXT,
    current_project_address TEXT,
    phone_number TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_crew_loc_org ON crew_locations(org_id);

-- Historical location log (append-only, 90-day retention)
CREATE TABLE IF NOT EXISTS location_history (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL,
    org_id UUID NOT NULL,
    session_id UUID,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    heading DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    recorded_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loc_history_user_time ON location_history(user_id, recorded_at DESC);

-- RLS: users can only see crew_locations for their own org
ALTER TABLE crew_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own org crew locations"
ON crew_locations FOR SELECT
USING (org_id IN (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Users can upsert own location"
ON crew_locations FOR INSERT
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own location"
ON crew_locations FOR UPDATE
USING (user_id = auth.uid());

-- RLS for location_history
ALTER TABLE location_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own org location history"
ON location_history FOR SELECT
USING (org_id IN (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Users can insert own location history"
ON location_history FOR INSERT
WITH CHECK (user_id = auth.uid());
