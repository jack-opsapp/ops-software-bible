-- SPEC Phase 1 launch gate — RLS audit lockdown
-- Source: ops-software-bible/SPEC/07_ROLLOUT.md § 13 + § 13A
-- See ops-software-bible/migrations/2026-05-26-01-spec-phase1-rls-audit-lockdown.sql for the canonical mirror

set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- ─── 0. Canonical OPS-internal admin gate ─────────────────────────────
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
  'Canonical OPS-internal admin gate. Returns true iff the calling user''s JWT email matches a row in public.admins. Does NOT trust customer-company admin status (unlike private.current_user_is_admin()). Mirror of OPS-Web isAdminEmail(). Added 2026-05-26 RLS audit lockdown.';

-- ─── CATEGORY A — OPS-internal-only (24) ──────────────────────────────

alter table public.admins enable row level security;
drop policy if exists admins_ops_admin_all on public.admins;
create policy admins_ops_admin_all on public.admins
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.admins from anon;

alter table public.stripe_webhook_events enable row level security;
drop policy if exists stripe_webhook_events_ops_admin_all on public.stripe_webhook_events;
create policy stripe_webhook_events_ops_admin_all on public.stripe_webhook_events
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.stripe_webhook_events from anon;

alter table public.feature_flags enable row level security;
drop policy if exists feature_flags_ops_admin_all on public.feature_flags;
create policy feature_flags_ops_admin_all on public.feature_flags
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.feature_flags from anon;

alter table public.feature_flag_overrides enable row level security;
drop policy if exists ffo_self_select on public.feature_flag_overrides;
create policy ffo_self_select on public.feature_flag_overrides
  for select to authenticated using (user_id = private.get_current_user_id());
drop policy if exists ffo_ops_admin_all on public.feature_flag_overrides;
create policy ffo_ops_admin_all on public.feature_flag_overrides
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.feature_flag_overrides from anon;

alter table public.app_settings enable row level security;
drop policy if exists app_settings_ops_admin_all on public.app_settings;
create policy app_settings_ops_admin_all on public.app_settings
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.app_settings from anon;

alter table public.analytics_events enable row level security;
drop policy if exists analytics_events_ops_admin_all on public.analytics_events;
create policy analytics_events_ops_admin_all on public.analytics_events
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.analytics_events from anon;

alter table public.ab_config enable row level security;
drop policy if exists ab_config_ops_admin_all on public.ab_config;
create policy ab_config_ops_admin_all on public.ab_config
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.ab_config from anon;

alter table public.ab_tests enable row level security;
drop policy if exists ab_tests_ops_admin_all on public.ab_tests;
create policy ab_tests_ops_admin_all on public.ab_tests
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.ab_tests from anon;

alter table public.ab_variants enable row level security;
drop policy if exists ab_variants_ops_admin_all on public.ab_variants;
create policy ab_variants_ops_admin_all on public.ab_variants
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.ab_variants from anon;

alter table public.ab_events enable row level security;
drop policy if exists ab_events_ops_admin_all on public.ab_events;
create policy ab_events_ops_admin_all on public.ab_events
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.ab_events from anon;

alter table public.contact_messages enable row level security;
drop policy if exists contact_messages_ops_admin_all on public.contact_messages;
create policy contact_messages_ops_admin_all on public.contact_messages
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.contact_messages from anon;

alter table public.ops_contacts enable row level security;
drop policy if exists ops_contacts_ops_admin_all on public.ops_contacts;
create policy ops_contacts_ops_admin_all on public.ops_contacts
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.ops_contacts from anon;

alter table public.blog_topics enable row level security;
drop policy if exists blog_topics_ops_admin_all on public.blog_topics;
create policy blog_topics_ops_admin_all on public.blog_topics
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.blog_topics from anon;

alter table public.blog_posts enable row level security;
drop policy if exists blog_posts_ops_admin_all on public.blog_posts;
create policy blog_posts_ops_admin_all on public.blog_posts
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.blog_posts from anon;

alter table public.blog_categories enable row level security;
drop policy if exists blog_categories_ops_admin_all on public.blog_categories;
create policy blog_categories_ops_admin_all on public.blog_categories
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.blog_categories from anon;

alter table public.course_challenges enable row level security;
drop policy if exists course_challenges_ops_admin_all on public.course_challenges;
create policy course_challenges_ops_admin_all on public.course_challenges
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.course_challenges from anon;

alter table public.email_audience_templates enable row level security;
drop policy if exists email_audience_templates_ops_admin_all on public.email_audience_templates;
create policy email_audience_templates_ops_admin_all on public.email_audience_templates
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.email_audience_templates from anon;

alter table public.email_jobs enable row level security;
drop policy if exists email_jobs_ops_admin_all on public.email_jobs;
create policy email_jobs_ops_admin_all on public.email_jobs
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.email_jobs from anon;

alter table public.email_campaigns enable row level security;
drop policy if exists email_campaigns_ops_admin_all on public.email_campaigns;
create policy email_campaigns_ops_admin_all on public.email_campaigns
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.email_campaigns from anon;

alter table public.email_pause_state enable row level security;
drop policy if exists email_pause_state_ops_admin_all on public.email_pause_state;
create policy email_pause_state_ops_admin_all on public.email_pause_state
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.email_pause_state from anon;

alter table public.email_pause_audit_log enable row level security;
drop policy if exists email_pause_audit_log_ops_admin_all on public.email_pause_audit_log;
create policy email_pause_audit_log_ops_admin_all on public.email_pause_audit_log
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.email_pause_audit_log from anon;

alter table public.email_anomaly_log enable row level security;
drop policy if exists email_anomaly_log_ops_admin_all on public.email_anomaly_log;
create policy email_anomaly_log_ops_admin_all on public.email_anomaly_log
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.email_anomaly_log from anon;

alter table public.email_suppressions enable row level security;
drop policy if exists email_suppressions_ops_admin_all on public.email_suppressions;
create policy email_suppressions_ops_admin_all on public.email_suppressions
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.email_suppressions from anon;

alter table public.email_template_versions enable row level security;
drop policy if exists email_template_versions_ops_admin_all on public.email_template_versions;
create policy email_template_versions_ops_admin_all on public.email_template_versions
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.email_template_versions from anon;

alter table public.trial_expiry_notifications enable row level security;
drop policy if exists trial_expiry_notifications_ops_admin_all on public.trial_expiry_notifications;
create policy trial_expiry_notifications_ops_admin_all on public.trial_expiry_notifications
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.trial_expiry_notifications from anon;

-- ─── CATEGORY B — Engagement-scoped (2) ───────────────────────────────

alter table public.gmail_scan_jobs enable row level security;
drop policy if exists gmail_scan_jobs_company_select on public.gmail_scan_jobs;
create policy gmail_scan_jobs_company_select on public.gmail_scan_jobs
  for select to authenticated using (company_id = private.get_user_company_id()::text);
drop policy if exists gmail_scan_jobs_ops_admin_all on public.gmail_scan_jobs;
create policy gmail_scan_jobs_ops_admin_all on public.gmail_scan_jobs
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.gmail_scan_jobs from anon;

alter table public.portal_branding enable row level security;
drop policy if exists company_access on public.portal_branding;
drop policy if exists portal_branding_company_all on public.portal_branding;
create policy portal_branding_company_all on public.portal_branding
  for all to authenticated
  using (company_id = private.get_user_company_id()::text)
  with check (company_id = private.get_user_company_id()::text);
drop policy if exists portal_branding_ops_admin_all on public.portal_branding;
create policy portal_branding_ops_admin_all on public.portal_branding
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.portal_branding from anon;

-- ─── CATEGORY C — Per-user (2) ────────────────────────────────────────

alter table public.lesson_progress enable row level security;
drop policy if exists lesson_progress_self_all on public.lesson_progress;
create policy lesson_progress_self_all on public.lesson_progress
  for all to authenticated
  using (user_id = public.get_user_id())
  with check (user_id = public.get_user_id());
drop policy if exists lesson_progress_ops_admin_all on public.lesson_progress;
create policy lesson_progress_ops_admin_all on public.lesson_progress
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.lesson_progress from anon;

alter table public.challenge_attempts enable row level security;
drop policy if exists challenge_attempts_self_all on public.challenge_attempts;
create policy challenge_attempts_self_all on public.challenge_attempts
  for all to authenticated
  using (user_id = public.get_user_id())
  with check (user_id = public.get_user_id());
drop policy if exists challenge_attempts_ops_admin_all on public.challenge_attempts;
create policy challenge_attempts_ops_admin_all on public.challenge_attempts
  for all to authenticated using (private.is_ops_admin()) with check (private.is_ops_admin());
revoke all on public.challenge_attempts from anon;

-- ─── CATEGORY D — Auth / permission (2) ───────────────────────────────

alter table public.user_roles enable row level security;
drop policy if exists user_roles_self_select on public.user_roles;
create policy user_roles_self_select on public.user_roles
  for select to authenticated using (user_id = public.get_user_id());
drop policy if exists user_roles_ops_admin_all on public.user_roles;
create policy user_roles_ops_admin_all on public.user_roles
  for all to authenticated
  using (private.is_ops_admin() or private.is_spec_operator())
  with check (private.is_ops_admin() or private.is_spec_operator());
revoke all on public.user_roles from anon;

alter table public.role_permissions enable row level security;
drop policy if exists role_permissions_self_roles_select on public.role_permissions;
create policy role_permissions_self_roles_select on public.role_permissions
  for select to authenticated using (
    role_id in (
      select ur.role_id from public.user_roles ur
      where ur.user_id = public.get_user_id()
    )
  );
drop policy if exists role_permissions_ops_admin_all on public.role_permissions;
create policy role_permissions_ops_admin_all on public.role_permissions
  for all to authenticated
  using (private.is_ops_admin() or private.is_spec_operator())
  with check (private.is_ops_admin() or private.is_spec_operator());
revoke all on public.role_permissions from anon;
