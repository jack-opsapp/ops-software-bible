-- SPEC Phase 1 — Migration 7/8: Public board snapshot + refresh function + pg_cron + CONCRETE RLS per table
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md § Public board snapshot + § RLS and server-route default
-- Applied: 2026-05-25 via Supabase MCP apply_migration as `spec_phase1_snapshot_and_rls`.
-- CR-3: snapshot TABLE (not view), refreshed every 5 min by pg_cron via private.refresh_spec_board_snapshot()
-- SPEC-SECURITY-DEFINER-PRIVATE-SCHEMA: function lives in private schema, EXECUTE granted to service_role only.
-- SPEC-SERVER-ROUTES-VS-RAW-RLS-DECISION: anon/authenticated cannot SELECT/INSERT any SPEC table
--   except spec_public_board_snapshot (sanitized aggregate-only).

-- ─── Snapshot table ──────────────────────────────────────────────────────
create table public.spec_public_board_snapshot (
  id boolean primary key default true check (id = true),
  data jsonb not null,
  refreshed_at timestamptz not null default now()
);

insert into public.spec_public_board_snapshot (id, data, refreshed_at)
values (true, '[]'::jsonb, now())
on conflict (id) do nothing;

grant select on public.spec_public_board_snapshot to anon, authenticated;

-- ─── Refresh function in private schema (SECURITY DEFINER) ───────────────
create or replace function private.refresh_spec_board_snapshot()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_data jsonb;
begin
  select jsonb_agg(jsonb_build_object(
    'tier', cap.tier,
    'availability',
      case
        when cap.is_accepting_bookings = false then 'CLOSED'
        when coalesce(p.active_ct, 0) < cap.slot_ceiling then 'OPEN'
        when coalesce(p.active_ct, 0) = cap.slot_ceiling
             and coalesce(p.queue_ct, 0) = 0 then 'LIMITED'
        else 'WAITLIST'
      end,
    'waitlist_bucket',
      case
        when coalesce(p.queue_ct, 0) = 0 then '0'
        when coalesce(p.queue_ct, 0) <= 2 then '1-2'
        else '3+'
      end,
    'next_start_week',
      case
        when cap.manual_next_start_override is not null
          then to_char(cap.manual_next_start_override, 'IYYY-IW')
        else to_char(
          coalesce(
            p.min_completion,
            current_date + (cap.discovery_days_max + cap.build_days_min) * interval '1 day'
          ),
          'IYYY-IW'
        )
      end,
    'is_accepting_bookings', cap.is_accepting_bookings,
    'public_note', cap.public_note
  ))
  into v_data
  from public.spec_capacity cap
  left join lateral (
    select
      -- Slot-consuming: discovery, building, ops_blocked hold (MJ-1, CR-3)
      count(*) filter (
        where sp.status in ('discovery', 'building')
           or (sp.status = 'on_hold' and sp.hold_type = 'ops_blocked')
      ) as active_ct,
      -- Queue: awaiting_deposit + deposit_paid (locked: MJ-1)
      count(*) filter (
        where sp.status in ('awaiting_deposit', 'deposit_paid')
      ) as queue_ct,
      min(sp.estimated_completion_date) filter (
        where sp.status in ('discovery', 'building')
           or (sp.status = 'on_hold' and sp.hold_type = 'ops_blocked')
      ) as min_completion
    from public.spec_projects sp
    where sp.tier = cap.tier
      and sp.is_test = false
  ) p on true;

  insert into public.spec_public_board_snapshot (id, data, refreshed_at)
  values (true, coalesce(v_data, '[]'::jsonb), now())
  on conflict (id) do update
    set data = excluded.data,
        refreshed_at = excluded.refreshed_at;
end;
$$;

grant execute on function private.refresh_spec_board_snapshot() to service_role;

-- pg_cron job — refresh every 5 minutes.
select cron.schedule(
  'spec_board_snapshot_refresh',
  '*/5 * * * *',
  $cron$ select private.refresh_spec_board_snapshot(); $cron$
);

-- Initial population (the cron picks up the next 5-min window).
select private.refresh_spec_board_snapshot();

-- ─── Enable RLS on every SPEC table ──────────────────────────────────────
alter table public.spec_capacity                 enable row level security;
alter table public.spec_projects                 enable row level security;
alter table public.spec_owner_approval_requests  enable row level security;
alter table public.spec_scope_documents          enable row level security;
alter table public.spec_acceptance_events        enable row level security;
alter table public.spec_module_entitlements      enable row level security;
alter table public.spec_payments                 enable row level security;
alter table public.spec_change_orders            enable row level security;
alter table public.spec_feature_acceptance       enable row level security;
alter table public.spec_satisfaction_ratings     enable row level security;
alter table public.spec_support_tickets          enable row level security;
alter table public.spec_retainers                enable row level security;
alter table public.spec_communications           enable row level security;
alter table public.spec_refund_requests          enable row level security;
alter table public.spec_referrals                enable row level security;
alter table public.spec_blocked_buyers           enable row level security;
alter table public.spec_public_board_snapshot    enable row level security;

-- ─── Operator-only policies on every engagement table ────────────────────
create policy "spec_capacity operator all" on public.spec_capacity
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_projects operator all" on public.spec_projects
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_owner_approval_requests operator all" on public.spec_owner_approval_requests
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_scope_documents operator all" on public.spec_scope_documents
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_acceptance_events operator all" on public.spec_acceptance_events
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_module_entitlements operator all" on public.spec_module_entitlements
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_payments operator all" on public.spec_payments
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_change_orders operator all" on public.spec_change_orders
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_feature_acceptance operator all" on public.spec_feature_acceptance
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_satisfaction_ratings operator all" on public.spec_satisfaction_ratings
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_support_tickets operator all" on public.spec_support_tickets
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_retainers operator all" on public.spec_retainers
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_communications operator all" on public.spec_communications
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_refund_requests operator all" on public.spec_refund_requests
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_referrals operator all" on public.spec_referrals
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

create policy "spec_blocked_buyers operator all" on public.spec_blocked_buyers
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());

-- Snapshot table: public SELECT (sanitized data), operator-only writes.
create policy "spec_public_board_snapshot public read" on public.spec_public_board_snapshot
  for select using (true);

create policy "spec_public_board_snapshot operator write" on public.spec_public_board_snapshot
  for all using (private.is_spec_operator())
  with check (private.is_spec_operator());
