-- SYNC RECOVERY T1 · M2
-- public.link_deck_design_to_opportunity_guarded(p_design_id, p_target_opportunity_id)
--
-- RC3 (2026-07-22 outage): iOS stripped opportunity_id from deck-design create/update
-- payloads, orphaning 15 designs server-side; a post-hoc PATCH of opportunity_id is
-- blocked by trg_deck_designs_guard_opportunity_reparent (token-guarded). This RPC is
-- the sanctioned, orphan-only link path: it mints the exact child-reparent token the
-- guard consumes, performs the guarded UPDATE, and cleans up — mirroring the
-- reassign_opportunity_email_thread_guarded / mint_email_review_child_reparent_tokens
-- token dance, scoped to a single deck_designs row.
--
-- Orphan-only + idempotent: links NULL -> target only. Re-linking to the same target
-- returns already_linked:true (safe retry). Linking a design already bound to a
-- DIFFERENT lead raises 23514 (moving between leads stays forbidden).
--
-- Auth is enforced in-body (SECURITY DEFINER): actor+company via private helpers,
-- deck edit right via private.current_user_can_edit_deck_design, opportunity edit
-- right via private.user_can_edit_opportunity. Grant mirrors create_opportunity_guarded
-- exactly (EXECUTE to authenticated; the iOS Firebase-bridged JWT carries
-- role=authenticated for guarded RPC calls).

create or replace function public.link_deck_design_to_opportunity_guarded(
  p_design_id uuid,
  p_target_opportunity_id uuid
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
declare
  v_actor_user_id uuid := private.get_current_user_id();
  v_company_id uuid := private.get_user_company_id();
  v_design public.deck_designs%rowtype;
  v_target public.opportunities%rowtype;
begin
  if v_actor_user_id is null or v_company_id is null then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  if p_design_id is null or p_target_opportunity_id is null then
    raise exception 'design_and_target_required'
      using errcode = '22023';
  end if;

  -- Canonical lock order: company serialization, then the child (design) row,
  -- then the target opportunity row. Matches the sibling reparent RPC ordering.
  perform private.lock_lead_assignment_company(v_company_id);

  select *
    into v_design
    from public.deck_designs d
   where d.id = p_design_id
   for update;
  if not found then
    raise exception 'deck_design_not_found'
      using errcode = 'P0002';
  end if;
  if v_design.company_id is distinct from v_company_id
     or v_design.deleted_at is not null then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  -- Idempotent retry: already linked to the requested target.
  if v_design.opportunity_id is not distinct from p_target_opportunity_id then
    return jsonb_build_object(
      'ok', true,
      'already_linked', true,
      'design_id', p_design_id,
      'opportunity_id', p_target_opportunity_id
    );
  end if;

  -- Orphan-only: never move a design that already belongs to another lead.
  if v_design.opportunity_id is not null then
    raise exception 'design already linked to another lead'
      using errcode = '23514';
  end if;

  if not private.current_user_can_edit_deck_design(
       v_company_id,
       null::uuid,
       v_design.project_id,
       'deck_builder.edit'
     ) then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  select *
    into v_target
    from public.opportunities o
   where o.id = p_target_opportunity_id
   for update;
  if not found or v_target.company_id is distinct from v_company_id then
    raise exception 'target opportunity not found in company scope'
      using errcode = 'P0002';
  end if;
  if v_target.archived_at is not null or v_target.deleted_at is not null then
    raise exception 'target opportunity is archived or deleted'
      using errcode = '23514';
  end if;

  if not private.user_can_edit_opportunity(v_actor_user_id, p_target_opportunity_id) then
    raise exception 'access_denied'
      using errcode = '42501';
  end if;

  -- Mint the single child-reparent token the guard trigger will consume on the
  -- UPDATE below (old NULL -> new target). On-conflict upsert mirrors the mint
  -- helper so a retry within the same (txid, backend_pid) is safe.
  insert into private.opportunity_child_reparent_tokens (
    transaction_id,
    backend_pid,
    table_name,
    row_id,
    old_opportunity_id,
    new_opportunity_id
  ) values (
    txid_current(),
    pg_backend_pid(),
    'deck_designs',
    p_design_id,
    null,
    p_target_opportunity_id
  )
  on conflict (transaction_id, backend_pid, table_name, row_id)
  do update set old_opportunity_id = excluded.old_opportunity_id,
                new_opportunity_id = excluded.new_opportunity_id;

  update public.deck_designs
     set opportunity_id = p_target_opportunity_id
   where id = p_design_id;

  delete from private.opportunity_child_reparent_tokens token
   where token.transaction_id = txid_current()
     and token.backend_pid = pg_backend_pid();

  return jsonb_build_object(
    'ok', true,
    'already_linked', false,
    'design_id', p_design_id,
    'opportunity_id', p_target_opportunity_id
  );
exception when others then
  delete from private.opportunity_child_reparent_tokens token
   where token.transaction_id = txid_current()
     and token.backend_pid = pg_backend_pid();
  raise;
end;
$function$;

-- Grant mirrors create_opportunity_guarded exactly: EXECUTE to authenticated (+ owner
-- postgres) only. Supabase ALTER DEFAULT PRIVILEGES auto-grants EXECUTE on new public.*
-- functions to anon/authenticated/service_role, so those are revoked to reach the same
-- hardened ACL the sibling create RPC carries. In prod this was applied as two
-- migrations (create, then the revoke); folded here into one self-contained file.
revoke execute on function public.link_deck_design_to_opportunity_guarded(uuid, uuid) from public;
revoke execute on function public.link_deck_design_to_opportunity_guarded(uuid, uuid) from anon;
revoke execute on function public.link_deck_design_to_opportunity_guarded(uuid, uuid) from service_role;
grant execute on function public.link_deck_design_to_opportunity_guarded(uuid, uuid) to authenticated;
