-- SPEC v2 payment/care engagement state (10_TIER_MODEL_V2.md § 6, 2026-07-14)
-- Additive-only, nullable (shared-DB discipline).
begin;
alter table public.spec_projects
  add column if not exists locked_total_cents integer,
  add column if not exists white_label boolean not null default false,
  add column if not exists care_monthly_cents integer,
  add column if not exists care_started_at timestamptz;
comment on column public.spec_projects.locked_total_cents is 'v2: SPEC-03 total locked at scope sign-off; null = floor pricing applies (10_TIER_MODEL_V2 § 2)';
comment on column public.spec_projects.white_label is 'v2: SPEC-03 white-label add-on (+$4,000 one-time, +$200/mo care bump) (10_TIER_MODEL_V2 § 3)';
comment on column public.spec_projects.care_monthly_cents is 'v2: care plan monthly cents copied from capacity at insert (+ white-label bump); null = no care plan (10_TIER_MODEL_V2 § 6)';
comment on column public.spec_projects.care_started_at is 'v2: stamped when the support window ends and care billing starts (10_TIER_MODEL_V2 § 6)';
commit;
