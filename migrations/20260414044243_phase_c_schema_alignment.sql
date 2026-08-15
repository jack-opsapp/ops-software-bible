-- 053_phase_c_schema_alignment.sql
-- Reconciliation migration for Phase C schema additions.
-- Fully idempotent: all operations use IF NOT EXISTS / IF EXISTS guards.

CREATE TABLE IF NOT EXISTS graph_entities (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  entity_type     TEXT NOT NULL,
  name            TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  email           TEXT,
  properties      JSONB DEFAULT '{}',
  confidence      FLOAT NOT NULL DEFAULT 0.5,
  source          TEXT,
  embedding       vector(1536),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'graph_entities_company_type_name_unique'
  ) THEN
    ALTER TABLE graph_entities
      ADD CONSTRAINT graph_entities_company_type_name_unique
      UNIQUE (company_id, entity_type, normalized_name);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ge_company ON graph_entities(company_id);
CREATE INDEX IF NOT EXISTS idx_ge_type ON graph_entities(company_id, entity_type);
CREATE INDEX IF NOT EXISTS idx_ge_email ON graph_entities(company_id, email) WHERE email IS NOT NULL;

ALTER TABLE graph_entities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Company-scoped entities" ON graph_entities;
CREATE POLICY "Company-scoped entities" ON graph_entities
  FOR ALL USING (company_id = (auth.jwt()->>'company_id')::uuid);

ALTER TABLE agent_knowledge_graph
  ADD COLUMN IF NOT EXISTS source_entity_id UUID REFERENCES graph_entities(id) ON DELETE SET NULL;

ALTER TABLE agent_knowledge_graph
  ADD COLUMN IF NOT EXISTS target_entity_id UUID REFERENCES graph_entities(id) ON DELETE SET NULL;

ALTER TABLE agent_knowledge_graph
  ADD COLUMN IF NOT EXISTS link_type TEXT;

ALTER TABLE agent_knowledge_graph
  ADD COLUMN IF NOT EXISTS confidence FLOAT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'akg_entity_edge_unique'
  ) THEN
    ALTER TABLE agent_knowledge_graph
      ADD CONSTRAINT akg_entity_edge_unique
      UNIQUE (company_id, source_entity_id, predicate, target_entity_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_akg_source_entity ON agent_knowledge_graph(source_entity_id) WHERE source_entity_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_akg_target_entity ON agent_knowledge_graph(target_entity_id) WHERE target_entity_id IS NOT NULL;

ALTER TABLE agent_writing_profiles
  ADD COLUMN IF NOT EXISTS profile_type TEXT NOT NULL DEFAULT 'general';

DO $$
DECLARE
  old_constraint_name TEXT;
BEGIN
  SELECT conname INTO old_constraint_name
  FROM pg_constraint
  WHERE conrelid = 'agent_writing_profiles'::regclass
    AND contype = 'u'
    AND array_length(conkey, 1) = 2
  LIMIT 1;

  IF old_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE agent_writing_profiles DROP CONSTRAINT %I', old_constraint_name);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'awp_company_user_profile_type_unique'
  ) THEN
    ALTER TABLE agent_writing_profiles
      ADD CONSTRAINT awp_company_user_profile_type_unique
      UNIQUE (company_id, user_id, profile_type);
  END IF;
END $$;

ALTER TABLE agent_memories
  ADD COLUMN IF NOT EXISTS entity_id UUID REFERENCES graph_entities(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_am_entity ON agent_memories(entity_id) WHERE entity_id IS NOT NULL;

CREATE OR REPLACE FUNCTION match_memories(
  query_embedding vector(1536),
  match_company_id UUID,
  match_threshold FLOAT DEFAULT 0.3,
  match_count INT DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  memory_type TEXT,
  category TEXT,
  content TEXT,
  confidence FLOAT,
  source TEXT,
  decay_score FLOAT,
  entity_id UUID,
  access_count INT,
  similarity FLOAT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    am.id,
    am.memory_type,
    am.category,
    am.content,
    am.confidence,
    am.source,
    am.decay_score,
    am.entity_id,
    am.access_count,
    1 - (am.embedding <=> query_embedding) AS similarity
  FROM agent_memories am
  WHERE am.company_id = match_company_id
    AND am.embedding IS NOT NULL
    AND am.decay_score > 0.1
    AND 1 - (am.embedding <=> query_embedding) > match_threshold
  ORDER BY am.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

CREATE OR REPLACE FUNCTION increment_access_count(memory_ids UUID[])
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE agent_memories
  SET access_count = access_count + 1,
      last_accessed_at = now()
  WHERE id = ANY(memory_ids);
END;
$$;
