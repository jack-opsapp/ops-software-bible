-- Catalog Setup Phase 5 runtime access reconciliation.
-- P5-19R source-of-truth draft only. Do not apply without explicit PM approval.
--
-- Why this exists:
-- During approved P5-19 authenticated iOS runtime QA, the iOS app authenticated
-- with Firebase JWTs while Supabase PostgREST evaluated requests under the
-- anon database role. The Phase 5 RPC and permission bootstrap surfaces were
-- originally source-controlled for authenticated only, so the live runtime
-- required scoped anon grants/policies to let Firebase-bridged iOS reach the
-- same company-scoped RLS model.
--
-- Live audit reference:
-- - Project: ops-app / ijeekuhbatykdomumfjx
-- - public.catalog_setup_save(uuid,text,jsonb): SECURITY INVOKER, search_path
--   public, private, pg_temp, EXECUTE granted to anon/authenticated/service_role.
-- - public.catalog_setup_save_requests: RLS enabled; anon has SELECT, INSERT,
--   UPDATE only; write_guard still requires ops.catalog_setup_save_rpc = on.
-- - public.catalog_stock_unit_events: RLS enabled; anon has SELECT, INSERT only;
--   event references are checked against same-company stock unit and variant.
-- - public.catalog_stock_unit_events.created_by default is
--   private.get_current_user_id(), not auth.uid(), so Firebase non-UUID subjects
--   do not fail UUID casts.
-- - Permission bootstrap tables expose SELECT to anon with policies that resolve
--   the current OPS user through private.get_current_user_id().
--
-- Security note:
-- grant usage on schema private to anon mirrors the current live repair because
-- PostgREST must resolve private.get_current_user_id() and
-- private.get_user_company_id() inside RLS policies and invoker RPC execution.
-- That is broader than ideal because several private functions still have
-- default/public EXECUTE privileges. This migration reconciles source control
-- with live production; a separate hardening review should explicitly revoke
-- anon/PUBLIC EXECUTE from private functions that are not needed by Firebase
-- bridge policies before private schema usage is narrowed again.
--
-- Rollback plan, for PM-reviewed rollback only:
-- 1. Revoke anon EXECUTE on public.catalog_setup_save(uuid,text,jsonb).
-- 2. Revoke anon table privileges added here.
-- 3. Drop the firebase bridge anon policies added here.
-- 4. Revert catalog_stock_unit_events.created_by to auth.uid() only after iOS no
--    longer sends Firebase non-UUID subjects through this path.
-- 5. Revoke anon USAGE on schema private only after every Firebase bridge policy
--    has been removed or moved to a narrower helper surface.

begin;

-- Firebase-bridged iOS executes this invoker RPC through the anon DB role.
revoke all on function public.catalog_setup_save(uuid, text, jsonb) from public;
grant execute on function public.catalog_setup_save(uuid, text, jsonb) to anon;
grant execute on function public.catalog_setup_save(uuid, text, jsonb) to authenticated;

-- The invoker RPC and RLS policies call private identity helpers.
grant usage on schema private to anon;

-- Permission and feature-flag bootstrap reads for Firebase-bridged iOS runtime.
-- Keep these read-only for anon.
alter table public.user_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.feature_flags enable row level security;
alter table public.feature_flag_overrides enable row level security;

revoke all on table public.user_roles from anon;
revoke all on table public.role_permissions from anon;
revoke all on table public.feature_flags from anon;
revoke all on table public.feature_flag_overrides from anon;

grant select on table public.user_roles to anon;
grant select on table public.role_permissions to anon;
grant select on table public.feature_flags to anon;
grant select on table public.feature_flag_overrides to anon;

drop policy if exists "firebase bridge users read own role"
  on public.user_roles;
create policy "firebase bridge users read own role"
  on public.user_roles
  for select
  to anon
  using (
    user_id = (select private.get_current_user_id())::text
  );

drop policy if exists "firebase bridge users read own role permissions"
  on public.role_permissions;
create policy "firebase bridge users read own role permissions"
  on public.role_permissions
  for select
  to anon
  using (
    role_id in (
      select ur.role_id
      from public.user_roles ur
      where ur.user_id = (select private.get_current_user_id())::text
    )
  );

drop policy if exists "firebase bridge users read feature flags"
  on public.feature_flags;
create policy "firebase bridge users read feature flags"
  on public.feature_flags
  for select
  to anon
  using (
    (select private.get_current_user_id()) is not null
  );

drop policy if exists "firebase bridge users read own feature overrides"
  on public.feature_flag_overrides;
create policy "firebase bridge users read own feature overrides"
  on public.feature_flag_overrides
  for select
  to anon
  using (
    user_id = (select private.get_current_user_id())
  );

-- RPC idempotency ledger. Anon can reach only its own company rows through RLS,
-- and direct writes remain blocked unless catalog_setup_save sets the local
-- ops.catalog_setup_save_rpc guard flag.
alter table public.catalog_setup_save_requests enable row level security;

revoke all on table public.catalog_setup_save_requests from anon;
grant select, insert, update on table public.catalog_setup_save_requests to anon;

drop policy if exists "firebase bridge catalog setup requests company isolation"
  on public.catalog_setup_save_requests;
create policy "firebase bridge catalog setup requests company isolation"
  on public.catalog_setup_save_requests
  for all
  to anon
  using (
    company_id = private.get_user_company_id()
  )
  with check (
    company_id = private.get_user_company_id()
  );

-- Stock-unit lifecycle events. Anon is limited to read/append through the
-- invoker RPC path; both RLS and the existing trigger enforce same-company
-- stock unit and variant references.
alter table public.catalog_stock_unit_events enable row level security;

alter table public.catalog_stock_unit_events
  alter column created_by set default private.get_current_user_id();

revoke all on table public.catalog_stock_unit_events from anon;
grant select, insert on table public.catalog_stock_unit_events to anon;

drop policy if exists "firebase bridge stock unit events select company"
  on public.catalog_stock_unit_events;
create policy "firebase bridge stock unit events select company"
  on public.catalog_stock_unit_events
  for select
  to anon
  using (
    company_id = private.get_user_company_id()
  );

drop policy if exists "firebase bridge stock unit events insert company"
  on public.catalog_stock_unit_events;
create policy "firebase bridge stock unit events insert company"
  on public.catalog_stock_unit_events
  for insert
  to anon
  with check (
    company_id = private.get_user_company_id()
    and exists (
      select 1
      from public.catalog_stock_units unit_row
      where unit_row.id = catalog_stock_unit_events.catalog_stock_unit_id
        and unit_row.company_id = catalog_stock_unit_events.company_id
        and unit_row.catalog_variant_id = catalog_stock_unit_events.catalog_variant_id
    )
    and exists (
      select 1
      from public.catalog_variants variant_row
      where variant_row.id = catalog_stock_unit_events.catalog_variant_id
        and variant_row.company_id = catalog_stock_unit_events.company_id
    )
    and (
      related_catalog_stock_unit_id is null
      or exists (
        select 1
        from public.catalog_stock_units related_unit_row
        where related_unit_row.id = catalog_stock_unit_events.related_catalog_stock_unit_id
          and related_unit_row.company_id = catalog_stock_unit_events.company_id
      )
    )
  );

commit;
