-- Agent memory tables for AI email features (Plan 4).
-- agent_memories: stores extracted facts from outbound emails
-- agent_knowledge_graph: relationship edges between entities
-- agent_writing_profiles: per-user writing style for draft generation

-- Enable pgvector if not already enabled
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS agent_memories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id text,
  memory_type text NOT NULL DEFAULT 'fact',
  category text NOT NULL,
  content text NOT NULL,
  confidence numeric NOT NULL DEFAULT 0.5,
  source text NOT NULL DEFAULT 'email',
  source_id text,
  embedding vector(1536),
  access_count integer NOT NULL DEFAULT 0,
  last_accessed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_agent_memories_company_category ON agent_memories(company_id, category);
CREATE INDEX idx_agent_memories_company_confidence ON agent_memories(company_id, confidence DESC);

CREATE TABLE IF NOT EXISTS agent_knowledge_graph (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  subject_type text NOT NULL,
  subject_id text NOT NULL,
  predicate text NOT NULL,
  object_type text NOT NULL,
  object_id text NOT NULL,
  properties jsonb DEFAULT '{}',
  confidence numeric NOT NULL DEFAULT 0.5,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_to timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, subject_type, subject_id, predicate, object_type, object_id)
);

CREATE INDEX idx_agent_kg_company_subject ON agent_knowledge_graph(company_id, subject_type, subject_id);
CREATE INDEX idx_agent_kg_company_object ON agent_knowledge_graph(company_id, object_type, object_id);

CREATE TABLE IF NOT EXISTS agent_writing_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  greeting_patterns text[] DEFAULT '{}',
  closing_patterns text[] DEFAULT '{}',
  avg_sentence_length numeric DEFAULT 0,
  formality_score numeric DEFAULT 0.5,
  emails_analyzed integer NOT NULL DEFAULT 0,
  tone_traits jsonb DEFAULT '{}',
  vocabulary_preferences jsonb DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(company_id, user_id)
);

COMMENT ON TABLE agent_memories IS 'AI-extracted business facts from outbound emails';
COMMENT ON TABLE agent_knowledge_graph IS 'Entity relationships for contextual draft generation';
COMMENT ON TABLE agent_writing_profiles IS 'Per-user communication style profiles for voice matching';
