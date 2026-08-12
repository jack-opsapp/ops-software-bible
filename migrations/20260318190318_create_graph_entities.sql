CREATE TABLE graph_entities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id UUID NOT NULL REFERENCES companies(id),
    entity_type TEXT NOT NULL,
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    email TEXT,
    properties JSONB DEFAULT '{}',
    confidence REAL DEFAULT 1.0,
    source TEXT DEFAULT 'email_import',
    embedding vector(1536),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (company_id, entity_type, normalized_name)
);

CREATE INDEX idx_graph_entities_embedding ON graph_entities
    USING hnsw (embedding vector_cosine_ops);
CREATE INDEX idx_graph_entities_company ON graph_entities (company_id);
CREATE INDEX idx_graph_entities_type ON graph_entities (company_id, entity_type);
CREATE INDEX idx_graph_entities_email ON graph_entities (company_id, email) WHERE email IS NOT NULL;

ALTER TABLE graph_entities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Company members can view their entities"
    ON graph_entities FOR SELECT
    USING (company_id = (auth.jwt()->>'company_id')::uuid);

CREATE POLICY "Service role has full access to entities"
    ON graph_entities FOR ALL
    USING (auth.role() = 'service_role');
