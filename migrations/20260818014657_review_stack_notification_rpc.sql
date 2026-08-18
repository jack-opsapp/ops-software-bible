-- Review-stack rail notifications: narrow actor-derived RPC (bug filed
-- 2026-08-17: "iOS review-stack notifications silently dead").
-- 20260715180500_notification_creation_hardening revoked app-role INSERT on
-- public.notifications and dropped notifications_insert_company: all creation
-- must cross a narrow actor-derived RPC or a trusted service boundary. iOS
-- ReviewThresholdService kept inserting task_review_stack /
-- payment_review_stack / unscheduled_review_stack rows directly and has logged
-- [REVIEW_STACK] 42501 on every launch since. The hardening is correct and
-- stays; this adds the sanctioned surface the service must call instead.
--
-- Doctrine compliance (mirrors public.request_lockout_admin_notification):
--   * recipient is always the ACTOR (self-notification only) — derived from
--     private.get_current_user_id(); company derived from the actor's row;
--     neither is expressible via inputs.
--   * copy is FIXED per stack kind server-side; the only caller data that
--     reaches the row is a clamped non-negative count interpolated into the
--     fixed template.
--   * type is constrained to the three review-stack kinds — the RPC cannot
--     mint authority-looking types.
--   * navigation is fixed per kind via deep_link_type (taskReview /
--     paymentReview / unscheduledReview — the iOS rail renders its REVIEW
--     button from deep_link_type). action_url stays NULL: these are
--     phone-workflow surfaces, and notification_action_url_internal forbids
--     the legacy client's ops:// scheme anyway.
--   * dedupe honored server-side under a per-user+stack advisory xact lock
--     (the legacy client's check-then-insert raced): at most one UNREAD row
--     per stack kind; counts below the threshold mark unread rows read so the
--     rail clears without user action.
--
-- Contract: sync_review_stack_notification(p_stack, p_count) -> text action
-- ('created' | 'kept' | 'cleared' | 'noop'); raises 42501 when no actor
-- resolves, 22023 for an unknown stack kind. Threshold (5) now lives HERE —
-- retuning rail loudness is a server-side edit, and must never move the iOS
-- FAB unlock gate (ReviewUnlockThresholds), which is deliberately separate.

create or replace function public.sync_review_stack_notification(
  p_stack text,
  p_count integer
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_count integer;
  v_threshold constant integer := 5;
  v_title text;
  v_body text;
  v_deep_link text;
begin
  v_actor_id := private.get_current_user_id();

  select u.company_id
  into v_company_id
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  if p_stack not in ('task_review_stack', 'payment_review_stack', 'unscheduled_review_stack') then
    raise exception 'unknown review stack'
      using errcode = '22023';
  end if;

  v_count := greatest(coalesce(p_count, 0), 0);

  perform pg_advisory_xact_lock(hashtextextended(
    'review-stack:' || v_actor_id::text || ':' || p_stack,
    0
  ));

  if v_count < v_threshold then
    update public.notifications
       set is_read = true
     where user_id = v_actor_id::text
       and type = p_stack
       and is_read = false;
    if found then
      return 'cleared';
    end if;
    return 'noop';
  end if;

  if exists (
    select 1
    from public.notifications n
    where n.user_id = v_actor_id::text
      and n.type = p_stack
      and n.is_read = false
  ) then
    return 'kept';
  end if;

  if p_stack = 'task_review_stack' then
    v_title := 'TASKS PILING UP';
    v_body := v_count || ' past due. Close them out.';
    v_deep_link := 'taskReview';
  elsif p_stack = 'payment_review_stack' then
    v_title := 'CLOSEOUTS WAITING';
    v_body := v_count || ' completed. Review and close out.';
    v_deep_link := 'paymentReview';
  else
    v_title := 'LOOSE ENDS';
    v_body := v_count || ' tasks with no date or crew.';
    v_deep_link := 'unscheduledReview';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type
  ) values (
    v_actor_id::text, v_company_id::text, p_stack, v_title, v_body,
    false, true, v_deep_link
  );
  return 'created';
end;
$function$;

revoke all on function public.sync_review_stack_notification(text, integer) from public;
grant execute on function public.sync_review_stack_notification(text, integer) to anon, authenticated;
