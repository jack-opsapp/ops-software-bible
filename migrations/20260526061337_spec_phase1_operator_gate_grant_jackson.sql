-- SPEC Phase 1 — Corrective migration: grant Jackson spec.admin via user_permission_overrides
-- ROOT CAUSE: public.user_roles.user_id has a UNIQUE constraint (live-schema finding not in spec).
-- Jackson is already in user_roles as 'Operator' (role_id ..000000000004); the SPEC Operator
-- INSERT in spec_phase1_operator_gate silently no-op'd via ON CONFLICT DO NOTHING.
-- FIX: use user_permission_overrides — the exact path the spec specifies for "future delegated
-- SPEC operators" (see 02_DATA_MODEL.md § Operator gate). company_id is NOT NULL on the table;
-- by convention SPEC overrides carry company_id = OPS_OPERATIONS_COMPANY_ID.

insert into public.user_permission_overrides
  (id, user_id, company_id, permission, scope, granted, created_at, updated_at)
values (
  gen_random_uuid(),
  '1746a0c1-be43-45d6-ab4d-584e82594b1b',     -- Jackson (j4ckson.sweet@gmail.com)
  '00000000-0000-0000-0000-00000000000a',     -- OPS_OPERATIONS_COMPANY_ID
  'spec.admin',
  'all',
  true,
  now(),
  now()
)
on conflict do nothing;
