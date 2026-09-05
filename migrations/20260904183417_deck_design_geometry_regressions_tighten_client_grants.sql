-- Supabase default privileges hand anon/authenticated ALL on every new public
-- table. The regression log's own post-apply probe expects SELECT only, and it
-- did not pass: TRUNCATE, REFERENCES and TRIGGER were also granted. TRUNCATE
-- bypasses RLS entirely, so a client could erase the evidence this table exists
-- to preserve. Reduce to exactly SELECT.
revoke all on public.deck_design_geometry_regressions from anon, authenticated;
grant select on public.deck_design_geometry_regressions to anon, authenticated;
