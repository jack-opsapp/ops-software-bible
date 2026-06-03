-- OPS iOS Catalog P6-24
-- Forward-only ACL hardening for the task-completion stock-consumption RPC.
-- Keeps the public wrapper callable by authenticated app users only.

revoke execute on function public.complete_project_task(uuid, text, jsonb)
  from public, anon, authenticated, service_role;

grant execute on function public.complete_project_task(uuid, text, jsonb)
  to authenticated;

comment on function public.complete_project_task(uuid, text, jsonb)
  is 'P6 task-completion wrapper. Completes the task and consumes tracked stock in one transaction; execute is granted only to authenticated.';
