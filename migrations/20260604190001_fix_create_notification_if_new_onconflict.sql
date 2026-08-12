-- ============================================================================
-- Fix create_notification_if_new — ON CONFLICT arbiter could not be inferred
--
-- The function's arbiter was:
--   ON CONFLICT (user_id, company_id, type, title) WHERE is_read = false
-- Prod's only matching unique index, notifications_unread_title_dedup_without_key,
-- is partial on (is_read = false AND dedupe_key IS NULL) — added later by the
-- dedupe_key rework without updating this function. Because `is_read = false`
-- does not imply `dedupe_key IS NULL`, Postgres raised 42P10 ("there is no unique
-- or exclusion constraint matching the ON CONFLICT specification") on EVERY call,
-- silently breaking notification creation on all 5 callers (Stripe webhook,
-- join-company, data-setup, inventory deduction, notification-service).
--
-- The function omits dedupe_key on insert, so every row it writes has
-- dedupe_key IS NULL. Adding that term to the arbiter predicate matches the
-- existing index exactly and preserves the intended dedup semantics (one unread,
-- non-keyed notification per (user, company, type, title)).
-- Verified via EXPLAIN: arbiter now resolves to notifications_unread_title_dedup_without_key.
--
-- Signature, SECURITY DEFINER, search_path, and body are otherwise unchanged.
-- ============================================================================

begin;

create or replace function public.create_notification_if_new(
  p_user_id text,
  p_company_id text,
  p_type text,
  p_title text,
  p_body text,
  p_persistent boolean default false,
  p_action_url text default null::text,
  p_action_label text default null::text,
  p_project_id text default null::text
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  insert into notifications (user_id, company_id, type, title, body, is_read, persistent, action_url, action_label, project_id)
  values (p_user_id, p_company_id, p_type, p_title, p_body, false, p_persistent, p_action_url, p_action_label, p_project_id)
  on conflict (user_id, company_id, type, title) where is_read = false and dedupe_key is null
  do nothing;
end;
$function$;

commit;
