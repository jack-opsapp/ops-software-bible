
-- wizard_analytics INSERT policy was scoped to role {authenticated}, but the
-- iOS Firebase->Supabase JWT bridge does not set a role: authenticated claim
-- in the JWT, so requests run under the public/anon role and the policy was
-- never evaluated, causing every insert to be rejected.
--
-- Other write-enabled tables (projects, clients, project_tasks) use {public}
-- role with private.resolve_uid() to identify the user via the JWT email
-- claim. Matching that pattern here. Since wizard_analytics is write-only
-- telemetry (SELECT is already restricted to owned rows), the check only
-- needs to require a valid JWT with an email that resolves to a user row.

DROP POLICY IF EXISTS "Users can insert own wizard analytics" ON public.wizard_analytics;

CREATE POLICY "Users can insert own wizard analytics"
  ON public.wizard_analytics
  FOR INSERT
  TO public
  WITH CHECK (private.resolve_uid() IS NOT NULL);

