-- Reconcile production schema with migration 035 (ai_stage_confidence,
-- ai_stage_signals, detected_value on opportunities) and migration 036
-- (decay_score on agent_memories). These columns were defined in source but
-- missing from the live DB, causing:
--
--   - sync-engine.ts:1140-1141 AI stage writes to silently fail in the
--     "AI review error (non-fatal)" catch, losing both stage and ai_summary
--     updates in the same batch
--   - memory-service.ts:988,997,1004 getContextForDraft queries to crash
--   - match_memories() RPC body to crash (references am.decay_score in
--     SELECT list and WHERE clause)
--   - cron/memory-decay to return 500 daily across all three phases
--   - ai-draft-service.ts:759 content-correction memory inserts to fail
--
-- Fully idempotent — safe to re-run.

-- ─── opportunities: re-add Phase C AI columns from migration 035 ──────────

ALTER TABLE opportunities
  ADD COLUMN IF NOT EXISTS ai_stage_confidence FLOAT;

ALTER TABLE opportunities
  ADD COLUMN IF NOT EXISTS ai_stage_signals TEXT[];

ALTER TABLE opportunities
  ADD COLUMN IF NOT EXISTS detected_value INT;

COMMENT ON COLUMN opportunities.ai_stage_confidence IS
  'Confidence score [0,1] for the AI-derived stage recommendation. Written by sync-engine during Step 6 AI stage review. NULL means no AI evaluation has run.';

COMMENT ON COLUMN opportunities.ai_stage_signals IS
  'Array of short string tags indicating why the AI chose the current stage (e.g. "likely_won", "likely_lost", "ai_evaluated", "terminal_flag"). Freeform for now.';

COMMENT ON COLUMN opportunities.detected_value IS
  'AI-detected dollar value of the opportunity, extracted from email thread content. Integer cents or whole dollars — check opportunity-service mapper.';

-- ─── agent_memories: re-add decay_score from migration 036 ────────────────
--
-- Default 1.0 means "fresh / full confidence". New rows inserted before
-- this migration need to be backfilled to the default so existing code
-- that filters ".gt('decay_score', 0.1)" actually sees them after the
-- column is added. The DEFAULT 1.0 on the ALTER takes care of existing
-- rows automatically; we run the explicit UPDATE as belt-and-braces in
-- case Postgres populates NULL for existing rows under some edge.

ALTER TABLE agent_memories
  ADD COLUMN IF NOT EXISTS decay_score FLOAT NOT NULL DEFAULT 1.0;

UPDATE agent_memories
SET decay_score = 1.0
WHERE decay_score IS NULL;

COMMENT ON COLUMN agent_memories.decay_score IS
  'Memory freshness / confidence score in [0,1]. Starts at 1.0 on insert, decays daily in cron/memory-decay based on last_accessed_at. Memories with decay_score < 0.1 are pruned after 6 months. The match_memories RPC uses this to filter stale results from vector search.';

-- Re-install the match_memories RPC. The function body references
-- am.decay_score, so if the column was missing in prod the function body
-- was broken even though the signature was intact. Re-creating the body
-- now that the column exists makes the RPC callable again.

CREATE OR REPLACE FUNCTION public.match_memories(
  query_embedding vector,
  match_company_id UUID,
  match_threshold FLOAT DEFAULT 0.3,
  match_count INT DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  memory_type TEXT,
  category TEXT,
  content TEXT,
  confidence DOUBLE PRECISION,
  source TEXT,
  decay_score DOUBLE PRECISION,
  entity_id UUID,
  access_count INT,
  similarity DOUBLE PRECISION
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
    am.confidence::double precision,
    am.source,
    am.decay_score::double precision,
    am.entity_id,
    am.access_count,
    (1 - (am.embedding <=> query_embedding))::double precision AS similarity
  FROM agent_memories am
  WHERE am.company_id = match_company_id
    AND am.embedding IS NOT NULL
    AND am.decay_score > 0.1
    AND 1 - (am.embedding <=> query_embedding) > match_threshold
  ORDER BY am.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;
