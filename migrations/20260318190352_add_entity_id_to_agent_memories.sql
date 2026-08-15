ALTER TABLE agent_memories
    ADD COLUMN entity_id UUID REFERENCES graph_entities(id),
    ADD COLUMN valid_from TIMESTAMPTZ,
    ADD COLUMN valid_to TIMESTAMPTZ;

CREATE INDEX idx_agent_memories_entity ON agent_memories (entity_id) WHERE entity_id IS NOT NULL;
