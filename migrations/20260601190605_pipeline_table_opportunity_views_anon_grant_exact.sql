-- Make anon's opportunity_views ACL byte-identical to project_views (anon=r):
-- strip the residual TRIGGER/MAINTAIN metaprivileges left by the prior revoke,
-- then re-grant SELECT only. Mirrors the project_views foundation migration's
-- `revoke all on table ... from anon; grant select ... to anon;` exactly.
revoke all on table public.opportunity_views from anon;
grant select on table public.opportunity_views to anon;
