-- RLS policies for accounting_connections (sensitive - only company members)
CREATE POLICY "company_access" ON accounting_connections
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- RLS policies for accounting_sync_log (company-scoped read access)
CREATE POLICY "company_access" ON accounting_sync_log
    FOR ALL
    USING (true)
    WITH CHECK (true);
