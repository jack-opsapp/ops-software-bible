-- Performance: apply the (SELECT …) wrap to the two pre-existing
-- graph_entities policies so all RLS policies on the table are
-- consistent and fast. Recreates them with identical semantics.

DROP POLICY IF EXISTS "Company members can view their entities" ON graph_entities;
CREATE POLICY "Company members can view their entities" ON graph_entities
  FOR SELECT USING (company_id = ((SELECT auth.jwt())->>'company_id')::uuid);

DROP POLICY IF EXISTS "Service role has full access to entities" ON graph_entities;
CREATE POLICY "Service role has full access to entities" ON graph_entities
  FOR ALL USING ((SELECT auth.role()) = 'service_role');
