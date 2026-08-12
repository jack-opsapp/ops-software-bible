-- Performance: wrap auth.jwt() in (SELECT …) so Postgres caches the
-- result once per query instead of re-evaluating per row. This is the
-- fix for the `auth_rls_initplan` lint and matters most on agent_actions
-- (approval queue scans can touch hundreds of rows).

-- agent_actions
DROP POLICY IF EXISTS agent_actions_company_scope ON agent_actions;
CREATE POLICY agent_actions_company_scope ON agent_actions
  FOR ALL USING (company_id = ((SELECT auth.jwt())->>'company_id')::uuid);

-- agent_knowledge_graph
DROP POLICY IF EXISTS agent_knowledge_graph_company_scope ON agent_knowledge_graph;
CREATE POLICY agent_knowledge_graph_company_scope ON agent_knowledge_graph
  FOR ALL USING (company_id = ((SELECT auth.jwt())->>'company_id')::uuid);

-- agent_writing_profiles
DROP POLICY IF EXISTS agent_writing_profiles_company_scope ON agent_writing_profiles;
CREATE POLICY agent_writing_profiles_company_scope ON agent_writing_profiles
  FOR ALL USING (company_id = ((SELECT auth.jwt())->>'company_id')::uuid);

-- agent_memories
DROP POLICY IF EXISTS agent_memories_company_scope ON agent_memories;
CREATE POLICY agent_memories_company_scope ON agent_memories
  FOR ALL USING (company_id = ((SELECT auth.jwt())->>'company_id')::uuid);

-- graph_entities (the one I created in the 053 reconciliation)
DROP POLICY IF EXISTS "Company-scoped entities" ON graph_entities;
CREATE POLICY "Company-scoped entities" ON graph_entities
  FOR ALL USING (company_id = ((SELECT auth.jwt())->>'company_id')::uuid);
