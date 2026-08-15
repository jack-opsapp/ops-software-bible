-- The agent_knowledge_graph table has two generations of schema columns:
--   Legacy: subject_type, subject_id, object_type, object_id (text, NOT NULL)
--   Current: source_entity_id, target_entity_id (uuid, FK to graph_entities)
-- The Phase C code inserts only the current-generation columns, so every
-- edge write fails with 23502 null_violation and the errors are swallowed
-- by fire-and-forget .then(null, err) handlers. Drop NOT NULL on the
-- legacy columns so the current code path works.
ALTER TABLE public.agent_knowledge_graph
  ALTER COLUMN subject_type DROP NOT NULL,
  ALTER COLUMN subject_id DROP NOT NULL,
  ALTER COLUMN object_type DROP NOT NULL,
  ALTER COLUMN object_id DROP NOT NULL;
