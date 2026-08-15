-- Production hardening: enable RLS on the agent_* tables that the
-- Supabase security linter flagged as `rls_disabled_in_public`.
-- These tables are only written from server code that uses the service
-- role key (which bypasses RLS), so existing traffic is unaffected.
-- Client-facing reads now require a JWT with a matching company_id.

ALTER TABLE agent_knowledge_graph ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_writing_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_memories ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'agent_knowledge_graph_company_scope' AND tablename = 'agent_knowledge_graph'
  ) THEN
    CREATE POLICY agent_knowledge_graph_company_scope ON agent_knowledge_graph
      FOR ALL USING (company_id = (auth.jwt()->>'company_id')::uuid);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'agent_writing_profiles_company_scope' AND tablename = 'agent_writing_profiles'
  ) THEN
    CREATE POLICY agent_writing_profiles_company_scope ON agent_writing_profiles
      FOR ALL USING (company_id = (auth.jwt()->>'company_id')::uuid);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'agent_memories_company_scope' AND tablename = 'agent_memories'
  ) THEN
    CREATE POLICY agent_memories_company_scope ON agent_memories
      FOR ALL USING (company_id = (auth.jwt()->>'company_id')::uuid);
  END IF;
END $$;
