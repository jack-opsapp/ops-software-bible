-- =====================================================================
-- SPEC Phase 1 launch gate — RLS audit lockdown
-- Date: 2026-05-26
-- Source spec: ops-software-bible/SPEC/07_ROLLOUT.md § 13 + § 13A
-- Project: ijeekuhbatykdomumfjx (ops-app)
-- =====================================================================
--
-- The Supabase security advisor flagged 31 tables in `public` as
-- rls_disabled_in_public (level=ERROR). Running paid SPEC ads while
-- those tables are world-readable would be an unacceptable risk —
-- they intersect with the SPEC funnel (Stripe webhook events,
-- contact form data, blog content, A/B and analytics events, and
-- the email-infrastructure tables that drive transactional sends).
--
-- This migration:
--   1. Adds `private.is_ops_admin()` — the canonical OPS-internal
--      admin gate, keyed on `public.admins` membership by JWT email.
--      Mirrors the existing OPS-Web `isAdminEmail()` helper. Does
--      NOT consult `is_company_admin / account_holder_id / admin_ids`
--      (the trap that `private.current_user_is_admin()` falls into
--      and that necessitated `private.is_spec_operator()` for SPEC).
--   2. Enables RLS on every flagged table.
--   3. Adds CONCRETE policies (USING + WITH CHECK where applicable)
--      per the access-pattern decision recorded in
--      03_DATA_ARCHITECTURE.md § RLS coverage audit — Phase 1
--      launch gate (2026-05-26).
--   4. Revokes all from anon for every flagged table — server-side
--      consumers (ops-site `/api/contact`, ops-site `blog.ts`, OPS-Web
--      `analytics-actions.ts`, etc.) all use the service-role client
--      which bypasses RLS, so anon never needs direct access.
--
-- Access-pattern categories
-- -------------------------
-- A. OPS-internal-only (24 tables): ops_admin FOR ALL via
--    `private.is_ops_admin()`. Writes from the app side go through
--    server routes using service role (bypasses RLS).
-- B. Engagement-scoped (2 tables): company-member access via
--    `private.get_user_company_id()` + ops_admin override.
-- C. Per-user (2 tables): row-owner via `public.get_user_id()` +
--    ops_admin override.
-- D. Auth/permission tables (2 tables): user can read own rows;
--    full access for ops_admin OR spec_operator (SECURITY DEFINER
--    helpers bypass RLS as `postgres`, so the SPEC operator gate
--    keeps working).
--
-- Idempotency: every policy is dropped-if-exists then recreated.
-- The `is_ops_admin` function uses CREATE OR REPLACE. Enable-RLS
-- statements are idempotent (PG ignores re-enable of already-enabled).
-- =====================================================================

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- ---------------------------------------------------------------------
-- 0. Canonical OPS-internal admin gate
-- ---------------------------------------------------------------------
-- `private.current_user_is_admin()` is unsafe for OPS-internal gating
-- because it short-circuits to TRUE for any user matching is_company_admin,
-- account_holder_id, or admin_ids — i.e. any customer-company admin.
-- This new gate consults `public.admins` exclusively, matching the
-- OPS-Web `isAdminEmail()` consumer in lib/admin/admin-queries.ts.
-- Lives in the `private` schema per the OPS convention. The function
-- is SECURITY DEFINER and gets EXECUTE granted to `public` — anon
-- lacks USAGE on `private`, so this resolves to authenticated-only.

create or replace function private.is_ops_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

grant usage on schema private to authenticated, service_role;
grant execute on function private.is_ops_admin() to public;

comment on function private.is_ops_admin() is
  'Canonical OPS-internal admin gate. Returns true iff the calling user''s '
  'JWT email matches a row in public.admins. Does NOT trust customer-company '
  'admin status (unlike private.current_user_is_admin()). Mirror of the '
  'isAdminEmail() helper in OPS-Web/src/lib/admin/admin-queries.ts. Used by '
  'every public.<ops-internal> RLS policy added in the 2026-05-26 RLS audit '
  'lockdown migration.';

-- =====================================================================
-- CATEGORY A — OPS-internal-only tables (24)
-- ops_admin FOR ALL; service role bypasses RLS; anon REVOKEd.
-- =====================================================================

-- ─── 1. public.admins ─────────────────────────────────────────────────
-- Self-reference: the table that defines who is_ops_admin() recognises.
-- Once you are in admins you can manage the list.
alter table public.admins enable row level security;

drop policy if exists admins_ops_admin_all on public.admins;
create policy admins_ops_admin_all on public.admins
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.admins from anon;

-- ─── 2. public.stripe_webhook_events ──────────────────────────────────
-- Dedup table for incoming Stripe webhook events. Writes happen via the
-- service-role webhook handler; reads happen from /admin for debugging.
alter table public.stripe_webhook_events enable row level security;

drop policy if exists stripe_webhook_events_ops_admin_all on public.stripe_webhook_events;
create policy stripe_webhook_events_ops_admin_all on public.stripe_webhook_events
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.stripe_webhook_events from anon;

-- ─── 3. public.feature_flags ──────────────────────────────────────────
-- Global feature flag definitions. Routes + permissions columns leak
-- app architecture; should never be anon-readable.
alter table public.feature_flags enable row level security;

drop policy if exists feature_flags_ops_admin_all on public.feature_flags;
create policy feature_flags_ops_admin_all on public.feature_flags
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.feature_flags from anon;

-- ─── 4. public.feature_flag_overrides ─────────────────────────────────
-- Per-user override of a feature flag. Each user can see (read-only)
-- their own override row so the app can render override badges in
-- their own account UI. Writes are ops_admin only.
alter table public.feature_flag_overrides enable row level security;

drop policy if exists ffo_self_select on public.feature_flag_overrides;
create policy ffo_self_select on public.feature_flag_overrides
  for select to authenticated
  using (user_id = private.get_current_user_id());

drop policy if exists ffo_ops_admin_all on public.feature_flag_overrides;
create policy ffo_ops_admin_all on public.feature_flag_overrides
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.feature_flag_overrides from anon;

-- ─── 5. public.app_settings ───────────────────────────────────────────
-- Global app config (k/v jsonb). ops_admin only.
alter table public.app_settings enable row level security;

drop policy if exists app_settings_ops_admin_all on public.app_settings;
create policy app_settings_ops_admin_all on public.app_settings
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.app_settings from anon;

-- ─── 6. public.analytics_events ───────────────────────────────────────
-- Server-side analytics ingest (OPS-Web flushAnalyticsEvents writes via
-- service role). 8083 rows at audit time. Read-only for ops_admin.
alter table public.analytics_events enable row level security;

drop policy if exists analytics_events_ops_admin_all on public.analytics_events;
create policy analytics_events_ops_admin_all on public.analytics_events
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.analytics_events from anon;

-- ─── 7. public.ab_config ──────────────────────────────────────────────
-- Single-row config for the marketing-site A/B testing system.
alter table public.ab_config enable row level security;

drop policy if exists ab_config_ops_admin_all on public.ab_config;
create policy ab_config_ops_admin_all on public.ab_config
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.ab_config from anon;

-- ─── 8. public.ab_tests ───────────────────────────────────────────────
-- A/B test definitions for the marketing site.
alter table public.ab_tests enable row level security;

drop policy if exists ab_tests_ops_admin_all on public.ab_tests;
create policy ab_tests_ops_admin_all on public.ab_tests
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.ab_tests from anon;

-- ─── 9. public.ab_variants ────────────────────────────────────────────
-- Variants belonging to an ab_tests row. Contains AI reasoning + config
-- json that should not be visible to anon.
alter table public.ab_variants enable row level security;

drop policy if exists ab_variants_ops_admin_all on public.ab_variants;
create policy ab_variants_ops_admin_all on public.ab_variants
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.ab_variants from anon;

-- ─── 10. public.ab_events ─────────────────────────────────────────────
-- Marketing-site A/B event ingest (812 rows). Writes via service role
-- from marketing-site server routes; reads for the admin dashboard.
alter table public.ab_events enable row level security;

drop policy if exists ab_events_ops_admin_all on public.ab_events;
create policy ab_events_ops_admin_all on public.ab_events
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.ab_events from anon;

-- ─── 11. public.contact_messages ──────────────────────────────────────
-- Contact-form submissions. Writes via ops-site `/api/contact` route
-- using service role. Reads by ops_admin for triage.
alter table public.contact_messages enable row level security;

drop policy if exists contact_messages_ops_admin_all on public.contact_messages;
create policy contact_messages_ops_admin_all on public.contact_messages
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.contact_messages from anon;

-- ─── 12. public.ops_contacts ──────────────────────────────────────────
-- Internal contact directory (0 rows). ops_admin only.
alter table public.ops_contacts enable row level security;

drop policy if exists ops_contacts_ops_admin_all on public.ops_contacts;
create policy ops_contacts_ops_admin_all on public.ops_contacts
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.ops_contacts from anon;

-- ─── 13. public.blog_topics ───────────────────────────────────────────
-- CMS draft topic queue (29 rows). Not consumed by the marketing site;
-- internal editorial planning only. ops_admin only.
alter table public.blog_topics enable row level security;

drop policy if exists blog_topics_ops_admin_all on public.blog_topics;
create policy blog_topics_ops_admin_all on public.blog_topics
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.blog_topics from anon;

-- ─── 14. public.blog_posts ────────────────────────────────────────────
-- Blog content (61 rows). Confirmed via grep: every ops-site read
-- routes through getSupabaseAdmin() (service role) — see
-- ops-site/src/lib/blog.ts and src/components/shared/RelatedJournalPosts.tsx.
-- No client-side anon-key consumers. Locking to ops_admin keeps drafts
-- private and prevents accidental client-side leaks.
alter table public.blog_posts enable row level security;

drop policy if exists blog_posts_ops_admin_all on public.blog_posts;
create policy blog_posts_ops_admin_all on public.blog_posts
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.blog_posts from anon;

-- ─── 15. public.blog_categories ───────────────────────────────────────
-- Blog category lookup (6 rows). Same access pattern as blog_posts —
-- all marketing-site reads are server-side service role.
alter table public.blog_categories enable row level security;

drop policy if exists blog_categories_ops_admin_all on public.blog_categories;
create policy blog_categories_ops_admin_all on public.blog_categories
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.blog_categories from anon;

-- ─── 16. public.course_challenges ─────────────────────────────────────
-- ops-learn challenge definitions (1 row, fixture). No live consumers
-- — ops-learn sub-project is not yet implemented. Default to ops_admin
-- only; relax when ops-learn ships and we know the read pattern.
alter table public.course_challenges enable row level security;

drop policy if exists course_challenges_ops_admin_all on public.course_challenges;
create policy course_challenges_ops_admin_all on public.course_challenges
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.course_challenges from anon;

-- ─── 17. public.email_audience_templates ──────────────────────────────
-- Reusable audience filters for email campaigns (0 rows).
alter table public.email_audience_templates enable row level security;

drop policy if exists email_audience_templates_ops_admin_all on public.email_audience_templates;
create policy email_audience_templates_ops_admin_all on public.email_audience_templates
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.email_audience_templates from anon;

-- ─── 18. public.email_jobs ────────────────────────────────────────────
-- Per-recipient send queue (0 rows). Service role writes; ops_admin reads.
alter table public.email_jobs enable row level security;

drop policy if exists email_jobs_ops_admin_all on public.email_jobs;
create policy email_jobs_ops_admin_all on public.email_jobs
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.email_jobs from anon;

-- ─── 19. public.email_campaigns ───────────────────────────────────────
-- Campaign definitions + send counters (0 rows). ops_admin only.
alter table public.email_campaigns enable row level security;

drop policy if exists email_campaigns_ops_admin_all on public.email_campaigns;
create policy email_campaigns_ops_admin_all on public.email_campaigns
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.email_campaigns from anon;

-- ─── 20. public.email_pause_state ─────────────────────────────────────
-- Per-scope email pause flag (1 row). ops_admin manages the kill switch.
alter table public.email_pause_state enable row level security;

drop policy if exists email_pause_state_ops_admin_all on public.email_pause_state;
create policy email_pause_state_ops_admin_all on public.email_pause_state
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.email_pause_state from anon;

-- ─── 21. public.email_pause_audit_log ─────────────────────────────────
-- Pause/resume audit trail (0 rows). Service role writes; ops_admin reads.
alter table public.email_pause_audit_log enable row level security;

drop policy if exists email_pause_audit_log_ops_admin_all on public.email_pause_audit_log;
create policy email_pause_audit_log_ops_admin_all on public.email_pause_audit_log
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.email_pause_audit_log from anon;

-- ─── 22. public.email_anomaly_log ─────────────────────────────────────
-- Detected bounce/spam/anomaly events (0 rows). Service role writes;
-- ops_admin reads via /admin email-health dashboard.
alter table public.email_anomaly_log enable row level security;

drop policy if exists email_anomaly_log_ops_admin_all on public.email_anomaly_log;
create policy email_anomaly_log_ops_admin_all on public.email_anomaly_log
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.email_anomaly_log from anon;

-- ─── 23. public.email_suppressions ────────────────────────────────────
-- Address-level suppression list (2 rows). Reading this leaks who has
-- unsubscribed or bounced. Service role writes; ops_admin reads.
alter table public.email_suppressions enable row level security;

drop policy if exists email_suppressions_ops_admin_all on public.email_suppressions;
create policy email_suppressions_ops_admin_all on public.email_suppressions
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.email_suppressions from anon;

-- ─── 24. public.email_template_versions ───────────────────────────────
-- Template-content-hash registry (17 rows). Used at build time + ops
-- read for previews. Service role writes; ops_admin reads.
alter table public.email_template_versions enable row level security;

drop policy if exists email_template_versions_ops_admin_all on public.email_template_versions;
create policy email_template_versions_ops_admin_all on public.email_template_versions
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.email_template_versions from anon;

-- ─── 25. public.trial_expiry_notifications ────────────────────────────
-- Per-company tracking of trial-expiry notification fanout (7 rows).
-- Written by ops cron; read by ops_admin. Customers never read this
-- directly (they read the email).
alter table public.trial_expiry_notifications enable row level security;

drop policy if exists trial_expiry_notifications_ops_admin_all on public.trial_expiry_notifications;
create policy trial_expiry_notifications_ops_admin_all on public.trial_expiry_notifications
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.trial_expiry_notifications from anon;

-- =====================================================================
-- CATEGORY B — Engagement-scoped (per-company) tables
-- Company-member access via private.get_user_company_id();
-- ops_admin override; service role bypasses; anon REVOKEd.
-- =====================================================================

-- ─── 26. public.gmail_scan_jobs ───────────────────────────────────────
-- Per-company gmail-scan job queue (4 rows, 20 dead — actively used).
-- company_id is text; private.get_user_company_id() returns uuid.
-- Company members SELECT their own; service-role writes; ops_admin all.
alter table public.gmail_scan_jobs enable row level security;

drop policy if exists gmail_scan_jobs_company_select on public.gmail_scan_jobs;
create policy gmail_scan_jobs_company_select on public.gmail_scan_jobs
  for select to authenticated
  using (company_id = private.get_user_company_id()::text);

drop policy if exists gmail_scan_jobs_ops_admin_all on public.gmail_scan_jobs;
create policy gmail_scan_jobs_ops_admin_all on public.gmail_scan_jobs
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.gmail_scan_jobs from anon;

-- ─── 27. public.portal_branding ───────────────────────────────────────
-- Per-company customer-portal theming (4 rows). Has a pre-existing
-- inert policy `company_access` keyed on a JWT `company_id` claim that
-- OPS does not set — the policy never matches and the table currently
-- has RLS disabled (advisor lint `policy_exists_rls_disabled`). Drop
-- the broken policy, replace with the OPS-convention pattern.
-- Company members read; company admins write (any company-admin gate
-- happens at the app layer); ops_admin overrides.
alter table public.portal_branding enable row level security;

drop policy if exists company_access on public.portal_branding;
drop policy if exists portal_branding_company_all on public.portal_branding;
create policy portal_branding_company_all on public.portal_branding
  for all to authenticated
  using (company_id = private.get_user_company_id()::text)
  with check (company_id = private.get_user_company_id()::text);

drop policy if exists portal_branding_ops_admin_all on public.portal_branding;
create policy portal_branding_ops_admin_all on public.portal_branding
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.portal_branding from anon;

-- =====================================================================
-- CATEGORY C — Per-user tables
-- Row-owner via public.get_user_id() (returns text matching the
-- text user_id column); ops_admin override; anon REVOKEd.
-- =====================================================================

-- ─── 28. public.lesson_progress ───────────────────────────────────────
-- ops-learn per-user lesson progress (0 rows; sub-project not yet shipped).
-- user_id text NOT NULL stores users.id::text per OPS convention.
alter table public.lesson_progress enable row level security;

drop policy if exists lesson_progress_self_all on public.lesson_progress;
create policy lesson_progress_self_all on public.lesson_progress
  for all to authenticated
  using (user_id = public.get_user_id())
  with check (user_id = public.get_user_id());

drop policy if exists lesson_progress_ops_admin_all on public.lesson_progress;
create policy lesson_progress_ops_admin_all on public.lesson_progress
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.lesson_progress from anon;

-- ─── 29. public.challenge_attempts ────────────────────────────────────
-- ops-learn per-user challenge attempts (0 rows; sub-project not yet shipped).
alter table public.challenge_attempts enable row level security;

drop policy if exists challenge_attempts_self_all on public.challenge_attempts;
create policy challenge_attempts_self_all on public.challenge_attempts
  for all to authenticated
  using (user_id = public.get_user_id())
  with check (user_id = public.get_user_id());

drop policy if exists challenge_attempts_ops_admin_all on public.challenge_attempts;
create policy challenge_attempts_ops_admin_all on public.challenge_attempts
  for all to authenticated
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

revoke all on public.challenge_attempts from anon;

-- =====================================================================
-- CATEGORY D — Auth / permission tables
-- These are consulted by SECURITY DEFINER helpers (has_permission,
-- is_spec_operator, current_user_has_permission). Those bypass RLS as
-- `postgres`, so locking these down does NOT break the helpers. For
-- direct client reads: a user can see their own row, and ops_admin or
-- spec_operator can see everything. Anon REVOKEd.
-- =====================================================================

-- ─── 30. public.user_roles ────────────────────────────────────────────
-- (171 rows.) user_id text NOT NULL stores users.id::text.
-- Own-row SELECT for any authenticated user — supports any UI that
-- shows "the role(s) you hold". ops_admin / spec_operator manage all.
alter table public.user_roles enable row level security;

drop policy if exists user_roles_self_select on public.user_roles;
create policy user_roles_self_select on public.user_roles
  for select to authenticated
  using (user_id = public.get_user_id());

drop policy if exists user_roles_ops_admin_all on public.user_roles;
create policy user_roles_ops_admin_all on public.user_roles
  for all to authenticated
  using (private.is_ops_admin() or private.is_spec_operator())
  with check (private.is_ops_admin() or private.is_spec_operator());

revoke all on public.user_roles from anon;

-- ─── 31. public.role_permissions ──────────────────────────────────────
-- (315 rows.) Permission grants per role. A user can SELECT permission
-- rows for any role they hold (joined via user_roles). The subquery
-- against user_roles runs under the same RLS context, which permits
-- the user's own user_roles row by the policy above. ops_admin /
-- spec_operator manage all.
alter table public.role_permissions enable row level security;

drop policy if exists role_permissions_self_roles_select on public.role_permissions;
create policy role_permissions_self_roles_select on public.role_permissions
  for select to authenticated
  using (
    role_id in (
      select ur.role_id
      from public.user_roles ur
      where ur.user_id = public.get_user_id()
    )
  );

drop policy if exists role_permissions_ops_admin_all on public.role_permissions;
create policy role_permissions_ops_admin_all on public.role_permissions
  for all to authenticated
  using (private.is_ops_admin() or private.is_spec_operator())
  with check (private.is_ops_admin() or private.is_spec_operator());

revoke all on public.role_permissions from anon;

-- =====================================================================
-- Done — 31 tables locked, 1 helper added.
-- Verify via:
--   select count(*) from pg_policies where schemaname = 'public'
--     and tablename = any(array['admins', ...]);
--   select * from supabase_advisor_security_checks where issue = 'rls_disabled_in_public';
-- =====================================================================
