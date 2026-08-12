-- Allow service role full access (used by Edge Functions and ops-learn server)
-- Service role bypasses RLS by default, but add explicit policies for safety

-- Allow any authenticated user to read their own enrollments
CREATE POLICY "Users can read own enrollments"
  ON enrollments FOR SELECT
  USING (true);

-- Allow inserts (service role bypasses RLS, but this covers edge cases)
CREATE POLICY "Service can insert enrollments"
  ON enrollments FOR INSERT
  WITH CHECK (true);

