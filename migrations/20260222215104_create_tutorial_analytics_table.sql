CREATE TABLE tutorial_analytics (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id text,
  platform text NOT NULL,
  flow_type text NOT NULL,
  phase text NOT NULL,
  phase_index int NOT NULL,
  action text NOT NULL,
  duration_ms int,
  total_elapsed_ms int,
  session_id text NOT NULL,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE tutorial_analytics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anonymous inserts" ON tutorial_analytics
  FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "Allow authenticated inserts" ON tutorial_analytics
  FOR INSERT TO authenticated WITH CHECK (true);
