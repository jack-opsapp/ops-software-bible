-- Guarded, atomic booking of an accepted meeting proposal.
-- docs/inbox/confirmation-triggered-booking-spec.md § 6.3–6.4
--
-- Everything that decides whether a booking happens is re-checked here under a
-- row lock, so a replayed sync, a concurrent cycle, and a visit the operator
-- already entered by hand all converge on exactly one site visit.

create or replace function public.book_proposed_meeting_as_system(
  p_proposal_id uuid,
  p_accepted_message_id text,
  p_notes text
) returns table (booked boolean, site_visit_id uuid, guard_reason text)
language plpgsql
security definer
set search_path to 'public', 'private', 'pg_temp'
as $$
declare
  v_proposal public.meeting_proposals;
  v_client_id text;
  v_client_ref uuid;
  v_client text;
  v_existing uuid;
  v_visit uuid;
begin
  select * into v_proposal
    from public.meeting_proposals
   where id = p_proposal_id
     for update;

  if not found then
    return query select false, null::uuid, 'proposal_missing'::text;
    return;
  end if;

  -- A replayed acceptance must return the booking it already made, not a second one.
  if v_proposal.status <> 'pending' then
    return query select false, v_proposal.site_visit_id,
      (case when v_proposal.status = 'accepted' then 'already_booked'
            else 'proposal_not_pending' end)::text;
    return;
  end if;

  if v_proposal.proposed_start_at <= now() then
    update public.meeting_proposals
       set status = 'expired', updated_at = now()
     where id = v_proposal.id;
    return query select false, null::uuid, 'proposal_expired'::text;
    return;
  end if;

  select o.client_id::text, o.client_ref
    into v_client_id, v_client_ref
    from public.opportunities o
   where o.id = v_proposal.opportunity_id
     and o.company_id = v_proposal.company_id;

  -- Mirror `resolveGuardedOpportunityClientId`: a row whose populated mirrors
  -- disagree is not safe to denormalize. The visit is opportunity-scoped, so we
  -- leave the client columns null (as every existing row does) rather than
  -- block a booking over a denormalization.
  v_client := case
    when v_client_id is not null and v_client_ref is not null
         and v_client_id <> v_client_ref::text then null
    else coalesce(v_client_ref::text, v_client_id)
  end;

  -- Idempotent against re-sync AND against a visit the operator already booked
  -- by hand: anything within two hours of the proposed instant is the same visit.
  select sv.id into v_existing
    from public.site_visits sv
   where sv.company_id = v_proposal.company_id::text
     and sv.opportunity_id = v_proposal.opportunity_id
     and sv.deleted_at is null
     and sv.scheduled_at between v_proposal.proposed_start_at - interval '2 hours'
                             and v_proposal.proposed_start_at + interval '2 hours'
   limit 1;

  if v_existing is not null then
    update public.meeting_proposals
       set status = 'accepted',
           accepted_at = now(),
           accepted_message_id = p_accepted_message_id,
           site_visit_id = v_existing,
           updated_at = now()
     where id = v_proposal.id;
    return query select false, v_existing, 'visit_already_exists'::text;
    return;
  end if;

  insert into public.site_visits (
    company_id, opportunity_id, client_id, client_ref,
    scheduled_at, duration_minutes, status, notes, created_by
  ) values (
    v_proposal.company_id::text,
    v_proposal.opportunity_id,
    v_client,
    private.try_parse_uuid(v_client),
    v_proposal.proposed_start_at,
    v_proposal.duration_minutes,
    'scheduled',
    p_notes,
    -- Honest attribution: the operator proposed the time; the system only
    -- recorded the customer's yes.
    v_proposal.proposed_by_user_id::text
  ) returning id into v_visit;

  update public.meeting_proposals
     set status = 'accepted',
         accepted_at = now(),
         accepted_message_id = p_accepted_message_id,
         site_visit_id = v_visit,
         updated_at = now()
   where id = v_proposal.id;

  return query select true, v_visit, null::text;
end;
$$;

revoke all on function public.book_proposed_meeting_as_system(uuid, text, text)
  from public, anon, authenticated;
