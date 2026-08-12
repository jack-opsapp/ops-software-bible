ALTER TABLE agent_knowledge_graph
    ADD COLUMN source_entity_id UUID REFERENCES graph_entities(id),
    ADD COLUMN target_entity_id UUID REFERENCES graph_entities(id),
    ADD COLUMN link_type TEXT DEFAULT 'extracted';

ALTER TABLE agent_knowledge_graph
    ADD CONSTRAINT akg_entity_edge_unique
    UNIQUE (company_id, source_entity_id, predicate, target_entity_id);

CREATE INDEX idx_akg_source_entity ON agent_knowledge_graph (source_entity_id) WHERE source_entity_id IS NOT NULL;
CREATE INDEX idx_akg_target_entity ON agent_knowledge_graph (target_entity_id) WHERE target_entity_id IS NOT NULL;
