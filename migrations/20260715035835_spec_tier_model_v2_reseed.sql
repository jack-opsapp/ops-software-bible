-- SPEC tier model v2 re-seed (10_TIER_MODEL_V2.md § 2/§ 6, 2026-07-14)
-- Replaces v1 setup/build/enterprise with spec01/spec02/spec03.
-- Safe: spec_projects verified 0 rows (2026-07-14) — re-seed, not a data migration.
-- Tier CHECK constraints on spec_capacity + spec_projects retargeted to v2 slugs only
-- (zero live engagements; old slugs are invalid everywhere in v2).
-- subscription_multiplier_estimate is NOT NULL in live schema: seeded 0, retired from all published surfaces.
-- retainer_monthly_cents is NOT NULL: 0 = no care plan (spec01).
-- polish_hours_budget is NOT NULL, unpublished internal budget: v1 ladder (2/4/8) carried unchanged.
begin;
alter table public.spec_capacity drop constraint spec_capacity_tier_check;
alter table public.spec_projects drop constraint spec_projects_tier_check;
delete from public.spec_capacity where tier in ('setup','build','enterprise');
alter table public.spec_capacity add constraint spec_capacity_tier_check
  check (tier = any (array['spec01'::text, 'spec02'::text, 'spec03'::text]));
alter table public.spec_projects add constraint spec_projects_tier_check
  check (tier = any (array['spec01'::text, 'spec02'::text, 'spec03'::text]));
insert into public.spec_capacity
  (tier, slot_ceiling, is_accepting_bookings, discovery_days_min, discovery_days_max,
   build_days_min, build_days_max, support_window_days, total_price_cents,
   subscription_multiplier_estimate, retainer_monthly_cents, polish_hours_budget, admin_notes)
values
  ('spec01', 6, true,  2,  4,  3,  7, 30,  200000, 0,     0, 2, 'v2 WORKFLOWS — 50/50, no care plan'),
  ('spec02', 3, true,  5, 10, 15, 25, 60,  750000, 0, 39500, 4, 'v2 SYSTEMS — quarters, care $395/mo (2 change-hours)'),
  ('spec03', 1, true, 10, 15, 30, 60, 90, 2500000, 0, 75000, 8, 'v2 PROPRIETARY — total_price_cents is the FLOOR; locked at scope sign-off; care from $750/mo (3 change-hours); white label +$4,000/+$200');
select private.refresh_spec_board_snapshot();
commit;
