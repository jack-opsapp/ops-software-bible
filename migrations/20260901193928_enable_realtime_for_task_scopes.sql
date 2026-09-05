-- Enable Supabase Realtime postgres_changes for task_scopes so a scope checked
-- off by one crew member appears live on every other device on the visit.
-- REPLICA IDENTITY FULL is required for the company_id=eq filter to match on
-- UPDATE/DELETE (default = PK only would drop filtered delete/old-value
-- events), matching project_tasks. The table is new and small, so the extra
-- WAL per change is negligible.
--
-- Hard prerequisite for RealtimeProcessor.companyFilteredTables: subscribing to
-- a table that is NOT in this publication fails the CDC create_subscription and
-- takes down the ENTIRE shared channel (no realtime for any table).
ALTER TABLE public.task_scopes REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_scopes;
