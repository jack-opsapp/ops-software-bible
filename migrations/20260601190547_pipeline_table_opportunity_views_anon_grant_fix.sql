-- Corrective: Supabase default privileges auto-grant full DML to anon on new
-- public tables. The project_views foundation migration countered this with an
-- explicit `revoke all ... from anon` before granting only SELECT; the
-- opportunity_views migration omitted that revoke, so anon leaked INSERT/UPDATE/
-- DELETE/TRUNCATE/REFERENCES table privileges. RLS still blocks anon DML (the
-- manage policies are `to authenticated`), but the table grant must mirror
-- project_views exactly (anon SELECT only) for defense-in-depth.
revoke insert, update, delete, truncate, references on table public.opportunity_views from anon;
grant select on table public.opportunity_views to anon;
