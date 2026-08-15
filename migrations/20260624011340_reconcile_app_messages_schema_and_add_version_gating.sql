-- Reconcile public.app_messages with the iOS + web client schema, and add
-- version-gating fields for force-update. Table is empty (verified 0 rows),
-- so renames/drops carry no data risk.

-- 1. Rename legacy columns to the names both clients read/write.
alter table public.app_messages rename column type to message_type;
alter table public.app_messages rename column is_active to active;

-- 2. New messages start as drafts (inactive) and are deliberately published.
alter table public.app_messages alter column active set default false;
alter table public.app_messages alter column active set not null;

-- 3. Fields the iOS DTO + web admin already use.
alter table public.app_messages add column dismissable boolean not null default true;
alter table public.app_messages add column app_store_url text;
alter table public.app_messages add column target_user_types text[];

-- 4. Version gating: a message applies only to installs whose version falls
--    in [minimum_version, maximum_version). Either bound may be null (open).
--    For mandatory_update this is what makes the force-wall self-resolving:
--    a user who updates past minimum_version stops matching and is unblocked.
alter table public.app_messages add column minimum_version text;
alter table public.app_messages add column maximum_version text;

-- 5. Platform scoping so an iOS-only force-update never walls an Android user.
--    null = all platforms.
alter table public.app_messages add column platform text;

-- 6. Consolidate role targeting into the multi-select array both clients use.
--    Legacy single-role column superseded; drop to avoid two-columns-one-job drift.
alter table public.app_messages drop column target_role;

-- start_date / end_date / created_at / updated_at retained for scheduling + audit.

comment on table public.app_messages is 'In-app messages shown on app launch: force/optional update walls, maintenance notices, announcements. One row active at a time (enforced in app layer). Version-gated via minimum_version/maximum_version.';
comment on column public.app_messages.message_type is 'mandatory_update | optional_update | maintenance | announcement | info';
comment on column public.app_messages.dismissable is 'false = blocking wall (no dismiss); true = dismissable overlay';
comment on column public.app_messages.target_user_types is 'role allowlist: admin|owner|office|operator|crew|unassigned. null/empty = all roles';
comment on column public.app_messages.minimum_version is 'CFBundleShortVersionString floor; message applies only if installed >= this (semantic compare). null = no lower bound';
comment on column public.app_messages.maximum_version is 'version ceiling; message applies only if installed < this. null = no upper bound';
comment on column public.app_messages.platform is 'ios | android. null = all platforms';
comment on column public.app_messages.start_date is 'message starts showing at this time. null = immediately';
comment on column public.app_messages.end_date is 'message auto-expires at this time. null = never';
