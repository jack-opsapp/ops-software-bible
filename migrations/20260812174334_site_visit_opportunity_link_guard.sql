-- Site visits: the iOS capture flow attaches/reassigns/clears the lead on a
-- LIVE visit via plain updates (quick-start visits are born unlinked and
-- linked mid-visit). The generic token-only reparent guard therefore wedges
-- every quick-start visit's sync queue (114 ops on the founder's device,
-- 2026-08-12). Replace it on site_visits only with a permission-checked
-- guard scoped to live visits; completed/cancelled visits keep the token-only
-- lock. All other guarded tables are unchanged.

create or replace function private.guard_site_visit_opportunity_link()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $$
declare
  v_old_opportunity_id uuid := old.opportunity_id;
  v_new_opportunity_id uuid := new.opportunity_id;
  v_consumed boolean;
  v_actor_user_id uuid;
  v_company_id uuid;
  v_target public.opportunities%rowtype;
begin
  if v_old_opportunity_id is not distinct from v_new_opportunity_id then
    return new;
  end if;

  -- Path 1: minted token (admin/RPC flows) — identical semantics to
  -- private.guard_opportunity_child_reparent.
  delete from private.opportunity_child_reparent_tokens token
   where token.transaction_id = txid_current()
     and token.backend_pid = pg_backend_pid()
     and token.table_name = tg_table_name
     and token.row_id = old.id
     and token.old_opportunity_id is not distinct from v_old_opportunity_id
     and token.new_opportunity_id is not distinct from v_new_opportunity_id
  returning true into v_consumed;
  if found and coalesce(v_consumed, false) then
    return new;
  end if;

  -- Path 2: permission-checked change on a LIVE visit. Completed/cancelled
  -- visits are frozen evidence — token-only.
  if old.completed_at is not null
     or old.status::text not in ('scheduled', 'in_progress') then
    raise exception 'child_reparent_forbidden' using errcode = '42501';
  end if;

  v_actor_user_id := private.get_current_user_id();
  v_company_id := private.get_user_company_id();
  if v_actor_user_id is null or v_company_id is null then
    raise exception 'child_reparent_forbidden' using errcode = '42501';
  end if;
  if old.company_id is distinct from v_company_id::text then
    raise exception 'child_reparent_forbidden' using errcode = '42501';
  end if;
  if not private.current_user_can_edit_site_visit(
    old.company_id, v_old_opportunity_id, old.project_id, old.project_ref
  ) then
    raise exception 'child_reparent_forbidden' using errcode = '42501';
  end if;

  if v_new_opportunity_id is not null then
    select * into v_target
      from public.opportunities o
     where o.id = v_new_opportunity_id;
    if not found or v_target.company_id is distinct from v_company_id then
      raise exception 'child_reparent_forbidden' using errcode = '42501';
    end if;
    if v_target.archived_at is not null or v_target.deleted_at is not null then
      raise exception 'child_reparent_forbidden' using errcode = '42501';
    end if;
    if not private.user_can_edit_opportunity(v_actor_user_id, v_new_opportunity_id) then
      raise exception 'child_reparent_forbidden' using errcode = '42501';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_site_visits_guard_opportunity_reparent on public.site_visits;
create trigger trg_site_visits_guard_opportunity_reparent
  before update of opportunity_id on public.site_visits
  for each row
  execute function private.guard_site_visit_opportunity_link();

-- Custom checklist types: the CHECK constraint on site_visit_types calls
-- private.site_visit_type_fields_valid, which was EXECUTE-granted only to
-- postgres — every client-side insert fails with permission denied (32 ops
-- parked on the founder's device). CHECK constraints run as the invoking role.
grant execute on function private.site_visit_type_fields_valid(jsonb) to anon, authenticated, service_role;
