-- iOS notification-surface RPCs (bug e302355c: "Client-side notification
-- inserts fail silently").
--
-- 20260715180500_notification_creation_hardening revoked app-role INSERT on
-- public.notifications: all creation crosses a narrow actor-derived RPC or a
-- trusted service boundary. Web was rewired then; iOS never was — twelve iOS
-- surfaces kept inserting through NotificationRepository.createNotification
-- and have died 42501 since 2026-07-17 (push still fired where OneSignal is
-- wired; only the durable rail rows are missing). Surface #1 (review stacks)
-- was fixed 2026-08-17 by 20260818014657_review_stack_notification_rpc; this
-- migration adds the sanctioned surface for the remaining twelve, one narrow
-- RPC per surface shape.
--
-- Doctrine (mirrors sync_review_stack_notification and
-- request_lockout_admin_notification):
--   * actor identity from private.get_current_user_id(); company from the
--     actor's row; neither is expressible via inputs.
--   * recipients derived server-side — from note/photo/batch/event/project
--     rows or public.users_with_permission — never from caller input.
--   * copy is FIXED server-side; the only caller data that reaches a row is
--     clamped counts / validated dimension integers interpolated into the
--     fixed templates (the review-stack precedent).
--   * type is a server-side literal per RPC — callers cannot mint
--     authority-looking types.
--   * action_url is an internal path or NULL (notification_action_url_internal
--     forbids the legacy client's ops:// scheme). Web click-through mirrors
--     the live service lane: /dashboard?openProject=<id>&mode=view. iOS
--     navigates by deep_link_type, which keeps the shipped client values.
--   * dedupe: persistent surfaces hold at-most-one-unread under a per-actor
--     advisory xact lock and auto-clear at zero (review-stack shape);
--     event surfaces dedupe by dedupe_key / note anchor and ride the
--     platform's partial unique indexes via ON CONFLICT DO NOTHING.
--
-- Surfaces → functions:
--   AppState throttled review reminders  → sync_review_reminder_notification
--   AppState overdue invoices            → sync_overdue_invoice_notifications
--   SharePhotoFinalizer self-confirm     → notify_share_photos_finalized
--   Project/photo note fan-out           → notify_note_created
--   Expense envelope decisions           → notify_expense_batch_decision
--   Time-off review decision             → notify_time_off_decision
--   In-app photo upload crew broadcast   → notify_project_photos_added
--   Inventory threshold rail             → sync_threshold_alert_notification
--   LiDAR measurement capture            → notify_measurement_captured
--   LiDAR offline queue banner           → sync_measurement_pending_notification
--   LiDAR retries exhausted              → notify_measurement_sync_failed

-- ---------------------------------------------------------------------------
-- AppState periodic review reminders (self, non-persistent).
-- Kinds: projects_needing_tasks ("TASKS MISSING") and stale_estimate_review
-- ("Stale Estimates"). Cadence stays client-side (UserDefaults window keyed by
-- company reminder frequency — those knobs have no server columns); the RPC
-- adds the cross-device guarantee the client throttle can't: at most one
-- UNREAD reminder per kind, so a second device inside the same window returns
-- 'kept' instead of stacking a duplicate rail row.
create or replace function public.sync_review_reminder_notification(
  p_kind text,
  p_count integer,
  p_threshold_days integer default null
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_count integer;
  v_threshold integer;
  v_title text;
  v_body text;
  v_deep_link text;
  v_inserted integer := 0;
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

  if p_kind not in ('projects_needing_tasks', 'stale_estimate_review') then
    raise exception 'unknown review reminder kind'
      using errcode = '22023';
  end if;

  v_count := greatest(coalesce(p_count, 1), 1);
  v_threshold := least(greatest(coalesce(p_threshold_days, 30), 1), 365);

  perform pg_advisory_xact_lock(hashtextextended(
    'review-reminder:' || v_actor_id::text || ':' || p_kind,
    0
  ));

  if exists (
    select 1
    from public.notifications n
    where n.user_id = v_actor_id::text
      and n.type = p_kind
      and n.is_read = false
  ) then
    return 'kept';
  end if;

  if p_kind = 'projects_needing_tasks' then
    v_title := 'TASKS MISSING';
    v_body := v_count || ' accepted job'
      || case when v_count = 1 then '' else 's' end
      || ' with no tasks. Crew can''t see it.';
    v_deep_link := 'projectsNeedingTasks';
  else
    v_title := 'Stale Estimates';
    v_body := v_count || ' estimate'
      || case when v_count = 1 then '' else 's' end
      || ' sitting ' || v_threshold || '+ days without follow-up';
    v_deep_link := 'jobBoard';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type
  ) values (
    v_actor_id::text, v_company_id::text, p_kind, v_title, v_body,
    false, false, v_deep_link
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.sync_review_reminder_notification(text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_review_reminder_notification(text, integer, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Overdue-invoice rail for payment-permission holders (others, non-persistent).
-- The overdue set is computed HERE from public.invoices — the caller supplies
-- nothing. Mirror of iOS Invoice.isOverdue: a due date exists and has passed
-- (UTC-midnight semantics, matching the client's date decode), balance
-- outstanding, not void. Recipients are invoices.record_payment holders
-- (permission-derived, never role), excluding the actor whose device noticed.
-- Dedupe: stable per-company key + a 24-hour per-recipient window (lockout
-- archetype), so multi-device and multi-admin launches cannot stack rows.
-- Returns the recipient ids that received NEW rows so the client can aim the
-- companion OneSignal push at exactly the recipients the rail reached
-- (create_notification_if_new_with_status rationale).
create or replace function public.sync_overdue_invoice_notifications(
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_count integer;
  v_total numeric;
  v_title text;
  v_body text;
  v_dedupe_key text;
  v_created text[] := '{}'::text[];
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

  select count(*), coalesce(sum(i.balance_due), 0)
  into v_count, v_total
  from public.invoices i
  where i.company_id = v_company_id
    and i.deleted_at is null
    and i.due_date is not null
    and (i.due_date::timestamp at time zone 'utc') < now()
    and coalesce(i.balance_due, 0) > 0
    and lower(coalesce(i.status, '')) <> 'void';

  if v_count = 0 then
    return v_created;
  end if;

  v_title := 'Overdue Invoices';
  v_body := v_count || ' invoice'
    || case when v_count = 1 then '' else 's' end
    || ' overdue totalling $' || to_char(v_total, 'FM999,999,999,990.00');
  v_dedupe_key := 'invoice-overdue:' || v_company_id::text;

  perform pg_advisory_xact_lock(hashtextextended(v_dedupe_key, 0));

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, deep_link_type,
      action_url, action_label, dedupe_key
    )
    select
      u.id::text, v_company_id::text, 'invoice_overdue', v_title, v_body,
      false, false, 'invoices',
      '/invoices', 'VIEW', v_dedupe_key
    from public.users_with_permission(
      v_company_id, 'invoices.record_payment', 'all'
    ) permitted(user_id)
    join public.users u on u.id = permitted.user_id
    where u.company_id = v_company_id
      and u.id <> v_actor_id
      and u.deleted_at is null
      and coalesce(u.is_active, false)
      and not exists (
        select 1
        from public.notifications recent
        where recent.user_id = u.id::text
          and recent.company_id = v_company_id::text
          and recent.type = 'invoice_overdue'
          and recent.dedupe_key = v_dedupe_key
          and recent.created_at >= now() - interval '24 hours'
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.sync_overdue_invoice_notifications()
  from public, anon, authenticated, service_role;
grant execute on function public.sync_overdue_invoice_notifications()
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Share-extension completion confirmation (self, non-persistent). Confirms a
-- share landed on the project; the project title comes from the project row,
-- never the caller. Replaces the constraint-invalid ops:// action_url with
-- the live web lane's project click-through.
create or replace function public.notify_share_photos_finalized(
  p_project_id uuid,
  p_photo_count integer
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_project_title text;
  v_count integer;
  v_title text;
  v_body text;
  v_inserted integer := 0;
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

  select coalesce(nullif(btrim(p.title), ''), 'Untitled project')
  into v_project_title
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  v_count := least(greatest(coalesce(p_photo_count, 1), 1), 500);
  v_title := case when v_count = 1 then 'Photo added' else 'Photos added' end;
  v_body := case when v_count = 1
    then '1 photo on ' || v_project_title
    else v_count || ' photos on ' || v_project_title
  end;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, project_id, deep_link_type,
    action_url, action_label
  ) values (
    v_actor_id::text, v_company_id::text, 'photo_uploaded', v_title, v_body,
    false, false, p_project_id::text, 'projectNotes',
    '/dashboard?openProject=' || p_project_id::text || '&mode=view',
    'VIEW PROJECT'
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_share_photos_finalized(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_share_photos_finalized(uuid, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Note-created fan-out (others, non-persistent) — one RPC for the four dead
-- note surfaces. The caller supplies only the note id; author, company,
-- project, mention list, photo owner, and crew all come from rows the note
-- itself anchors:
--   * mentioned_user_ids on the note → 'mention' rows;
--   * photo note (photo_url set)     → photo owner from project_photos gets
--     'photo_comment' (unless author or already mentioned);
--   * plain note                     → project.team_member_ids broadcast gets
--     'project_note' (minus author and mentioned).
-- The actor must BE the note's author — the RPC cannot narrate anyone else's
-- note. System-event notes (event_kind set) never notify. Re-calls are
-- idempotent: a recipient with any row of that type anchored to this note_id
-- is skipped, so a transport retry cannot double-notify. Copy templates match
-- the shipped iOS client verbatim (straight quotes, '...' truncation at 100).
-- Per-note dedupe keys keep the platform's unread-title index from swallowing
-- a REAL mention on a second note while the first is unread.
-- Returns the recipients that received NEW rows, per type, for push targeting.
create or replace function public.notify_note_created(
  p_note_id uuid
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_actor_name text;
  v_note public.project_notes%rowtype;
  v_project public.projects%rowtype;
  v_project_title text;
  v_preview text;
  v_note_body text;
  v_mention_candidates text[] := '{}'::text[];
  v_mention_created text[] := '{}'::text[];
  v_team_created text[] := '{}'::text[];
  v_owner_id text;
  v_owner_created text;
  v_photo_count integer := 0;
  v_note_title text;
  v_action_url text;
  v_kind text;
begin
  v_actor_id := private.get_current_user_id();

  select
    u.company_id,
    coalesce(
      nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''),
      'A team member'
    )
  into v_company_id, v_actor_name
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_note
  from public.project_notes n
  where n.id = p_note_id
  for share;

  if not found
     or v_note.author_id is distinct from v_actor_id::text
     or v_note.company_id is distinct from v_company_id::text
     or v_note.deleted_at is not null
     or v_note.event_kind is not null then
    raise exception 'notification note is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_project
  from public.projects p
  where p.id::text = v_note.project_id
    and p.company_id = v_company_id
    and p.deleted_at is null
  for share;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  v_project_title := coalesce(
    nullif(btrim(v_project.title), ''),
    'Untitled project'
  );

  perform pg_advisory_xact_lock(hashtextextended(
    'note-created:' || p_note_id::text,
    0
  ));

  v_preview := btrim(coalesce(v_note.content, ''));
  if length(v_preview) > 100 then
    v_preview := substring(v_preview from 1 for 100) || '...';
  end if;
  if v_preview = '' then
    v_note_body := 'on ' || v_project_title;
  else
    v_note_body := '"' || v_preview || '" on ' || v_project_title;
  end if;

  v_action_url := '/dashboard?openProject=' || v_note.project_id || '&mode=view';

  select coalesce(array_agg(distinct candidate.user_id), '{}'::text[])
  into v_mention_candidates
  from unnest(coalesce(v_note.mentioned_user_ids, '{}'::text[]))
    as requested(user_id)
  join lateral (select lower(btrim(requested.user_id)) as user_id) candidate on true
  where candidate.user_id ~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and candidate.user_id <> v_actor_id::text
    and exists (
      select 1
      from public.users mention_user
      where mention_user.id = candidate.user_id::uuid
        and mention_user.company_id = v_company_id
        and mention_user.deleted_at is null
        and coalesce(mention_user.is_active, false)
    );

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, project_id, note_id, deep_link_type,
      action_url, action_label, dedupe_key
    )
    select
      mention.user_id, v_company_id::text, 'mention',
      v_actor_name || ' mentioned you', v_note_body,
      false, false, v_note.project_id, v_note.id::text, 'projectNotes',
      v_action_url, 'View Note', 'note-mention:' || v_note.id::text
    from unnest(v_mention_candidates) as mention(user_id)
    where not exists (
      select 1
      from public.notifications prior
      where prior.user_id = mention.user_id
        and prior.type = 'mention'
        and prior.note_id = v_note.id::text
    )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_mention_created
  from ins;

  if v_note.photo_url is not null then
    v_kind := 'photo_comment';

    select lower(btrim(photo.uploaded_by))
    into v_owner_id
    from public.project_photos photo
    where photo.project_id = v_note.project_id
      and photo.url = v_note.photo_url
      and photo.deleted_at is null
    order by photo.created_at desc nulls last
    limit 1;

    if v_owner_id is not null
       and v_owner_id ~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       and v_owner_id <> v_actor_id::text
       and v_owner_id <> all (v_mention_candidates)
       and exists (
         select 1
         from public.users owner_user
         where owner_user.id = v_owner_id::uuid
           and owner_user.company_id = v_company_id
           and owner_user.deleted_at is null
           and coalesce(owner_user.is_active, false)
       )
       and not exists (
         select 1
         from public.notifications prior
         where prior.user_id = v_owner_id
           and prior.type = 'photo_comment'
           and prior.note_id = v_note.id::text
       ) then
      insert into public.notifications (
        user_id, company_id, type, title, body,
        is_read, persistent, project_id, note_id, deep_link_type,
        action_url, action_label, dedupe_key
      ) values (
        v_owner_id, v_company_id::text, 'photo_comment',
        v_actor_name || ' commented on your photo', v_note_body,
        false, false, v_note.project_id, v_note.id::text, 'projectNotes',
        v_action_url, 'View Note', 'note-photo-comment:' || v_note.id::text
      )
      on conflict do nothing;
      if found then
        v_owner_created := v_owner_id;
      end if;
    end if;
  else
    v_kind := 'project_note';

    if jsonb_typeof(v_note.attachments) = 'array' then
      v_photo_count := jsonb_array_length(v_note.attachments);
    end if;

    v_note_title := v_actor_name || case
      when v_photo_count = 0 then ' added a note'
      when v_photo_count = 1 then ' added a photo'
      else ' added ' || v_photo_count || ' photos'
    end;

    with ins as (
      insert into public.notifications (
        user_id, company_id, type, title, body,
        is_read, persistent, project_id, note_id, deep_link_type,
        action_url, action_label, dedupe_key
      )
      select
        crew.user_id, v_company_id::text, 'project_note',
        v_note_title, v_note_body,
        false, false, v_note.project_id, v_note.id::text, 'projectNotes',
        v_action_url, 'View Note', 'note-activity:' || v_note.id::text
      from (
        select distinct lower(btrim(member.user_id)) as user_id
        from unnest(coalesce(v_project.team_member_ids, '{}'::text[]))
          as member(user_id)
      ) crew
      where crew.user_id ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        and crew.user_id <> v_actor_id::text
        and crew.user_id <> all (v_mention_candidates)
        and exists (
          select 1
          from public.users crew_user
          where crew_user.id = crew.user_id::uuid
            and crew_user.company_id = v_company_id
            and crew_user.deleted_at is null
            and coalesce(crew_user.is_active, false)
        )
        and not exists (
          select 1
          from public.notifications prior
          where prior.user_id = crew.user_id
            and prior.type = 'project_note'
            and prior.note_id = v_note.id::text
        )
      on conflict do nothing
      returning user_id
    )
    select coalesce(array_agg(user_id), '{}'::text[])
    into v_team_created
    from ins;
  end if;

  return jsonb_build_object(
    'kind', v_kind,
    'mention_user_ids', to_jsonb(v_mention_created),
    'photo_owner_id', v_owner_created,
    'team_user_ids', to_jsonb(v_team_created)
  );
end;
$function$;

revoke all on function public.notify_note_created(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_note_created(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Expense envelope decision → submitter (other, non-persistent). The actor
-- must hold expenses.approve at all-scope — the same gate as the operation
-- RPCs (approve_expense_batch / mark_expense_batch_paid) — and the claimed
-- decision must actually be recorded on the batch row, so the RPC cannot mint
-- decision claims that never happened. Web's approval surfaces dispatch their
-- own service-lane notifications after those shared RPCs, which is why the
-- notification does NOT live inside them — this narrow companion is the iOS
-- lane. Batch vocabulary (envelope console) is deliberately distinct from the
-- per-line copy of early_clear_expense_line.
create or replace function public.notify_expense_batch_decision(
  p_batch_id uuid,
  p_decision text,
  p_count integer default null
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_batch public.expense_batches%rowtype;
  v_count integer;
  v_latest_amendment integer;
  v_title text;
  v_body text;
  v_dedupe_key text;
  v_inserted integer := 0;
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

  if not public.has_permission(v_actor_id, 'expenses.approve', 'all') then
    raise exception 'notification actor lacks expenses.approve'
      using errcode = '42501';
  end if;

  if p_decision not in ('approved', 'sent_back', 'paid') then
    raise exception 'unknown expense batch decision'
      using errcode = '22023';
  end if;

  select *
  into v_batch
  from public.expense_batches b
  where b.id = p_batch_id
    and b.company_id = v_company_id;

  if v_batch.id is null then
    raise exception 'notification batch is unavailable'
      using errcode = '42501';
  end if;

  if v_batch.submitted_by is null
     or v_batch.submitted_by = v_actor_id
     or not exists (
       select 1
       from public.users submitter
       where submitter.id = v_batch.submitted_by
         and submitter.company_id = v_company_id
         and submitter.deleted_at is null
         and coalesce(submitter.is_active, false)
     ) then
    return 'noop';
  end if;

  if p_decision = 'approved' then
    if v_batch.status not in ('approved', 'auto_approved') then
      raise exception 'expense batch is not approved'
        using errcode = '22023';
    end if;
    v_title := 'Expenses Approved';
    v_body := 'Your batch ' || v_batch.batch_number || ' was approved';
    v_dedupe_key := 'expense_batch_approved:' || v_batch.id::text;
  elsif p_decision = 'sent_back' then
    select max(child.amendment_number)
    into v_latest_amendment
    from public.expense_batches child
    where child.parent_batch_id = v_batch.id;

    if v_latest_amendment is null then
      raise exception 'expense batch has no amendment'
        using errcode = '22023';
    end if;

    v_count := least(greatest(coalesce(p_count, 1), 1), 10000);
    v_title := 'Expenses Sent Back';
    v_body := v_count || ' expense'
      || case when v_count = 1 then '' else 's' end
      || ' on ' || v_batch.batch_number
      || ' need' || case when v_count = 1 then 's' else '' end
      || ' fixes';
    v_dedupe_key := 'expense_batch_sent_back:' || v_batch.id::text
      || ':' || v_latest_amendment;
  else
    if v_batch.paid_at is null then
      raise exception 'expense batch is not paid out'
        using errcode = '22023';
    end if;
    v_title := 'Expenses Paid Out';
    v_body := 'Your expense batch ' || v_batch.batch_number
      || ' has been paid out';
    v_dedupe_key := 'expense_batch_paid:' || v_batch.id::text;
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, batch_id, deep_link_type,
    action_url, action_label, dedupe_key
  ) values (
    v_batch.submitted_by::text, v_company_id::text,
    case p_decision
      when 'approved' then 'expense_approved'
      when 'sent_back' then 'expense_rejected'
      else 'expense_paid'
    end,
    v_title, v_body,
    false, false, v_batch.id::text, 'expense',
    '/accounting?tab=expenses', 'VIEW', v_dedupe_key
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_expense_batch_decision(uuid, text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_expense_batch_decision(uuid, text, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Time-off decision → requester (other, non-persistent). The decision must be
-- recorded on the event row and the ACTOR must be its recorded reviewer; the
-- recipient is the row's requester. A self-review creates no rail row (the
-- reviewer's feedback is their own action).
create or replace function public.notify_time_off_decision(
  p_event_id uuid
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_actor_name text;
  v_event public.calendar_user_events%rowtype;
  v_recipient text;
  v_event_title text;
  v_approved boolean;
  v_title text;
  v_body text;
  v_inserted integer := 0;
begin
  v_actor_id := private.get_current_user_id();

  select
    u.company_id,
    coalesce(
      nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''),
      'A team member'
    )
  into v_company_id, v_actor_name
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_event
  from public.calendar_user_events e
  where e.id = p_event_id
  for share;

  if not found
     or v_event.company_id is distinct from v_company_id::text
     or v_event.type is distinct from 'time_off'
     or v_event.deleted_at is not null then
    raise exception 'notification event is unavailable'
      using errcode = '42501';
  end if;

  if v_event.status not in ('approved', 'denied') then
    raise exception 'time off decision is not recorded'
      using errcode = '22023';
  end if;

  if v_event.reviewed_by is distinct from v_actor_id::text then
    raise exception 'notification actor is not the reviewer'
      using errcode = '42501';
  end if;

  v_recipient := lower(btrim(v_event.user_id));
  if v_recipient !~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or v_recipient = v_actor_id::text
     or not exists (
       select 1
       from public.users requester
       where requester.id = v_recipient::uuid
         and requester.company_id = v_company_id
         and requester.deleted_at is null
         and coalesce(requester.is_active, false)
     ) then
    return 'noop';
  end if;

  v_event_title := coalesce(nullif(btrim(v_event.title), ''), 'Time off');
  v_approved := v_event.status = 'approved';
  v_title := case when v_approved then 'Time Off Approved' else 'Time Off Denied' end;
  v_body := v_actor_name
    || case when v_approved then ' approved' else ' denied' end
    || ' your time off request: ' || v_event_title;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type,
    action_url, action_label, dedupe_key
  ) values (
    v_recipient, v_company_id::text,
    case when v_approved then 'time_off_approved' else 'time_off_denied' end,
    v_title, v_body,
    false, false, 'schedule',
    '/calendar', 'VIEW',
    'time-off-decision:' || v_event.id::text || ':' || v_event.status
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_time_off_decision(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_time_off_decision(uuid)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- In-app photo upload → assigned crew broadcast (others, non-persistent).
-- Recipients come from the project row's crew list, uploader name from the
-- actor's row, project title from the project row; the caller contributes only
-- the clamped count. Returns the recipients that received NEW rows for push
-- targeting. Unread duplicates are absorbed by the platform's
-- (user, company, type, title) unread index.
create or replace function public.notify_project_photos_added(
  p_project_id uuid,
  p_photo_count integer
) returns text[]
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_actor_name text;
  v_project public.projects%rowtype;
  v_project_title text;
  v_count integer;
  v_title text;
  v_body text;
  v_created text[] := '{}'::text[];
begin
  v_actor_id := private.get_current_user_id();

  select
    u.company_id,
    coalesce(
      nullif(btrim(concat_ws(' ', u.first_name, u.last_name)), ''),
      'A teammate'
    )
  into v_company_id, v_actor_name
  from public.users u
  where u.id = v_actor_id
    and u.company_id is not null
    and u.deleted_at is null
    and coalesce(u.is_active, false);

  if v_actor_id is null or v_company_id is null then
    raise exception 'notification actor is unavailable'
      using errcode = '42501';
  end if;

  select *
  into v_project
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null
  for share;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  v_project_title := coalesce(
    nullif(btrim(v_project.title), ''),
    'Untitled project'
  );
  v_count := least(greatest(coalesce(p_photo_count, 1), 1), 500);
  v_title := v_actor_name
    || case when v_count = 1 then ' added a photo' else ' added photos' end;
  v_body := case when v_count = 1
    then '1 photo on ' || v_project_title
    else v_count || ' photos on ' || v_project_title
  end;

  with ins as (
    insert into public.notifications (
      user_id, company_id, type, title, body,
      is_read, persistent, project_id, deep_link_type,
      action_url, action_label
    )
    select
      crew.user_id, v_company_id::text, 'photo_uploaded', v_title, v_body,
      false, false, p_project_id::text, 'projectNotes',
      '/dashboard?openProject=' || p_project_id::text || '&mode=view',
      'VIEW PROJECT'
    from (
      select distinct lower(btrim(member.user_id)) as user_id
      from unnest(coalesce(v_project.team_member_ids, '{}'::text[]))
        as member(user_id)
    ) crew
    where crew.user_id ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and crew.user_id <> v_actor_id::text
      and exists (
        select 1
        from public.users crew_user
        where crew_user.id = crew.user_id::uuid
          and crew_user.company_id = v_company_id
          and crew_user.deleted_at is null
          and coalesce(crew_user.is_active, false)
      )
    on conflict do nothing
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}'::text[])
  into v_created
  from ins;

  return v_created;
end;
$function$;

revoke all on function public.notify_project_photos_added(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_project_photos_added(uuid, integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Inventory threshold rail (self, persistent — review-stack shape). The
-- client reports the order-suggestion count after each sync; the server keeps
-- at most one UNREAD persistent alert and clears it when the count returns to
-- zero, replacing the client's racy check-then-insert plus its separate clear
-- call. The legacy ops://catalog/orders action_url is gone — iOS renders the
-- REVIEW action from deep_link_type; the surface is a phone workflow, so
-- action_url stays NULL.
create or replace function public.sync_threshold_alert_notification(
  p_count integer
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_count integer;
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

  v_count := greatest(coalesce(p_count, 0), 0);

  perform pg_advisory_xact_lock(hashtextextended(
    'threshold-alert:' || v_actor_id::text,
    0
  ));

  if v_count = 0 then
    update public.notifications
       set is_read = true
     where user_id = v_actor_id::text
       and type = 'threshold_alert'
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
      and n.type = 'threshold_alert'
      and n.is_read = false
  ) then
    return 'kept';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, deep_link_type, action_url, action_label
  ) values (
    v_actor_id::text, v_company_id::text, 'threshold_alert',
    '// ' || v_count || ' ITEM'
      || case when v_count = 1 then '' else 'S' end
      || ' BELOW THRESHOLD',
    'Tap to review and draft an order.',
    false, true, 'catalogOrders', null, 'REVIEW'
  );
  return 'created';
end;
$function$;

revoke all on function public.sync_threshold_alert_notification(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_threshold_alert_notification(integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- LiDAR measurement captured (self, non-persistent). Copy is the spec-verbatim
-- §6 template (2026-05-10 dimensioned-photo-capture design), rendered HERE;
-- the caller passes the validated dimension integers and kind, the project
-- title comes from the project row. The legacy ops:// action_url carried the
-- annotation id and was constraint-invalid — navigation is deep_link_type +
-- project_id on iOS, and the annotation id is deliberately not an input.
create or replace function public.notify_measurement_captured(
  p_project_id uuid,
  p_kind text,
  p_width_inches integer default null,
  p_height_inches integer default null,
  p_opening_type text default null,
  p_sill_inches integer default null,
  p_wall_width_feet integer default null,
  p_wall_width_inches integer default null,
  p_wall_height_feet integer default null
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_project_title text;
  v_body text;
  v_wall_width text;
  v_inserted integer := 0;
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

  select coalesce(nullif(btrim(p.title), ''), 'Untitled project')
  into v_project_title
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  if p_kind = 'opening' then
    if p_width_inches is null or p_width_inches not between 0 and 100000
       or p_height_inches is null or p_height_inches not between 0 and 100000
       or p_sill_inches is null or p_sill_inches not between 0 and 100000
       or p_opening_type is null
       or p_opening_type not in ('window', 'door') then
      raise exception 'invalid opening measurement'
        using errcode = '22023';
    end if;
    v_body := upper(v_project_title)
      || ' · ' || p_width_inches || '″×' || p_height_inches || '″ '
      || upper(p_opening_type)
      || ' · SILL ' || p_sill_inches || '″';
  elsif p_kind = 'wall_section' then
    if p_wall_width_feet is null or p_wall_width_feet not between 0 and 100000
       or p_wall_width_inches is null or p_wall_width_inches not between 0 and 100000
       or p_wall_height_feet is null or p_wall_height_feet not between 0 and 100000 then
      raise exception 'invalid wall section measurement'
        using errcode = '22023';
    end if;
    if p_wall_width_inches = 0 then
      v_wall_width := p_wall_width_feet || '′';
    else
      v_wall_width := p_wall_width_feet || '′' || p_wall_width_inches || '″';
    end if;
    v_body := upper(v_project_title)
      || ' · WALL SECTION · ' || v_wall_width
      || ' × ' || p_wall_height_feet || '′';
  else
    raise exception 'unknown measurement kind'
      using errcode = '22023';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, project_id, deep_link_type,
    action_url, action_label
  ) values (
    v_actor_id::text, v_company_id::text, 'measurement_captured',
    '// MEASUREMENT SAVED', v_body,
    false, false, p_project_id::text, 'projectDetails',
    null, 'VIEW'
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_measurement_captured(
  uuid, text, integer, integer, text, integer, integer, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.notify_measurement_captured(
  uuid, text, integer, integer, text, integer, integer, integer, integer
) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- LiDAR offline queue banner (self, persistent — review-stack shape). Depth
-- zero clears the banner; the legacy client had no clear lane at all, so the
-- spec's "auto-clear when the queue drains" finally has a server surface.
create or replace function public.sync_measurement_pending_notification(
  p_queue_depth integer
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_depth integer;
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

  v_depth := greatest(coalesce(p_queue_depth, 0), 0);

  perform pg_advisory_xact_lock(hashtextextended(
    'measurement-pending:' || v_actor_id::text,
    0
  ));

  if v_depth = 0 then
    update public.notifications
       set is_read = true
     where user_id = v_actor_id::text
       and type = 'measurement_pending_sync'
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
      and n.type = 'measurement_pending_sync'
      and n.is_read = false
  ) then
    return 'kept';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent
  ) values (
    v_actor_id::text, v_company_id::text, 'measurement_pending_sync',
    '// SYNC QUEUED',
    v_depth || ' MEASUREMENT'
      || case when v_depth = 1 then '' else 'S' end
      || ' · WILL UPLOAD ON SIGNAL',
    false, true
  );
  return 'created';
end;
$function$;

revoke all on function public.sync_measurement_pending_notification(integer)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_measurement_pending_notification(integer)
  to anon, authenticated;

-- ---------------------------------------------------------------------------
-- LiDAR retries exhausted (self, non-persistent). The annotation row may not
-- exist server-side when the insert itself is what failed, so the project id
-- is the only anchor; title comes from the project row.
create or replace function public.notify_measurement_sync_failed(
  p_project_id uuid
) returns text
language plpgsql security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
declare
  v_actor_id uuid;
  v_company_id uuid;
  v_project_title text;
  v_inserted integer := 0;
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

  select coalesce(nullif(btrim(p.title), ''), 'Untitled project')
  into v_project_title
  from public.projects p
  where p.id = p_project_id
    and p.company_id = v_company_id
    and p.deleted_at is null;

  if not found then
    raise exception 'notification project is unavailable'
      using errcode = '42501';
  end if;

  insert into public.notifications (
    user_id, company_id, type, title, body,
    is_read, persistent, project_id, deep_link_type,
    action_url, action_label
  ) values (
    v_actor_id::text, v_company_id::text, 'measurement_sync_failed',
    '// ERROR — SYNC FAILED',
    upper(v_project_title) || ' · MEASUREMENT NOT UPLOADED · RETRY',
    false, false, p_project_id::text, 'projectDetails',
    null, 'RETRY'
  )
  on conflict do nothing;

  get diagnostics v_inserted = row_count;
  if v_inserted = 1 then
    return 'created';
  end if;
  return 'noop';
end;
$function$;

revoke all on function public.notify_measurement_sync_failed(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.notify_measurement_sync_failed(uuid)
  to anon, authenticated;
