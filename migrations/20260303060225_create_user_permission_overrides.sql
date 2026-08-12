CREATE TABLE IF NOT EXISTS user_permission_overrides (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL,
  company_id   UUID NOT NULL,
  permission   TEXT NOT NULL,
  scope        TEXT,
  granted      BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE (user_id, permission)
);

CREATE INDEX IF NOT EXISTS idx_user_permission_overrides_user_id ON user_permission_overrides(user_id);

ALTER TABLE user_permission_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own overrides" ON user_permission_overrides
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Admins can manage overrides" ON user_permission_overrides
  FOR ALL USING (true);
