-- Atomic task-type reassignment and merge commands.
--
-- This migration is deliberately forward-only. The guards prevent new invalid
-- references, but they do not rewrite existing rows that point at a
-- soft-deleted task type.

create table if not exists private.task_type_mutation_receipts (
  company_id uuid not null references public.companies(id) on delete cascade,
  idempotency_key uuid not null,
  actor_user_id uuid not null,
  operation text not null check (operation in ('reassign', 'merge')),
  request_payload jsonb not null,
  response jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (company_id, idempotency_key)
);

alter table private.task_type_mutation_receipts enable row level security;

revoke all on table private.task_type_mutation_receipts
  from public, anon, authenticated;
grant select on table private.task_type_mutation_receipts to service_role;

create index if not exists project_tasks_active_task_type_idx
  on public.project_tasks (company_id, task_type_id)
  where deleted_at is null
    and task_type_id is not null;

create or replace function public.tg_task_type_reminders_soft_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deleted_at is null or old.deleted_at is not null then
    return new;
  end if;

  -- Retire every still-actionable reminder. Acknowledged, dismissed, and
  -- terminal-task reminders are history and must remain readable.
  update public.task_reminders reminder
  set deleted_at = new.deleted_at,
      updated_at = now()
  from public.project_tasks task
  where reminder.source_template_id = new.id
    and reminder.task_id = task.id
    and reminder.company_id = new.company_id
    and task.company_id = new.company_id
    and reminder.acknowledged_at is null
    and reminder.dismissed_at is null
    and reminder.deleted_at is null
    and task.status not in ('completed', 'cancelled');

  return new;
end;
$$;

create or replace function private.guard_project_task_task_type_reference()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_type_id uuid;
begin
  -- Deleting a historical task must remain possible even when its old type is
  -- already inactive.
  if new.deleted_at is not null then
    return new;
  end if;

  if new.task_type_id is null then
    return new;
  end if;

  select task_type.id
  into v_task_type_id
  from public.task_types task_type
  where task_type.id = new.task_type_id
    and task_type.company_id = new.company_id
    and task_type.deleted_at is null
  for key share;

  if v_task_type_id is null then
    raise exception using
      message = 'invalid_project_task_task_type',
      errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_project_task_task_type_reference()
  from public;

drop trigger if exists project_tasks_guard_task_type_reference
  on public.project_tasks;
create trigger project_tasks_guard_task_type_reference
  before insert or update of task_type_id, company_id, deleted_at on public.project_tasks
  for each row
  execute function private.guard_project_task_task_type_reference();

create or replace function private.guard_task_type_soft_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.deleted_at is not null or new.deleted_at is null then
    return new;
  end if;

  if coalesce(old.is_default, false)
     or coalesce(new.is_default, false) then
    raise exception using
      message = 'default_task_type_delete_forbidden',
      errcode = '23514';
  end if;

  if exists (
      select 1
      from public.project_tasks task
      where task.task_type_id = old.id
        and task.company_id = old.company_id
        and task.deleted_at is null
    )
    or exists (
      select 1
      from public.task_recurrences recurrence
      where recurrence.task_type_id = old.id
        and recurrence.company_id = old.company_id
        and recurrence.deleted_at is null
    )
    or exists (
      select 1
      from public.products product
      where product.company_id = old.company_id
        and product.deleted_at is null
        and (
          product.task_type_ref = old.id
          or product.task_type_id = old.id::text
          or (
            old.bubble_id is not null
            and product.task_type_id = old.bubble_id
          )
        )
    )
    or exists (
      select 1
      from public.task_templates template
      where template.company_id = old.company_id::text
        and template.deleted_at is null
        and (
          template.task_type_ref = old.id
          or template.task_type_id = old.id::text
          or (
            old.bubble_id is not null
            and template.task_type_id = old.bubble_id
          )
        )
    )
    or exists (
      select 1
      from public.task_type_reminders reminder_template
      where reminder_template.task_type_id = old.id
        and reminder_template.company_id = old.company_id
        and reminder_template.deleted_at is null
    )
    or exists (
      select 1
      from public.task_types dependent
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(dependent.dependencies) = 'array'
            then dependent.dependencies
          else '[]'::jsonb
        end
      ) dependency
      where dependent.id <> old.id
        and dependent.company_id = old.company_id
        and dependent.deleted_at is null
        and dependency ->> 'depends_on_task_type_id' = old.id::text
    )
    or exists (
      select 1
      from public.project_tasks task
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(task.dependency_overrides) = 'array'
            then task.dependency_overrides
          else '[]'::jsonb
        end
      ) dependency
      where task.company_id = old.company_id
        and task.deleted_at is null
        and dependency ->> 'depends_on_task_type_id' = old.id::text
    ) then
    raise exception using
      message = 'task_type_has_live_references',
      errcode = '23503';
  end if;

  return new;
end;
$$;

revoke all on function private.guard_task_type_soft_delete()
  from public;

drop trigger if exists task_types_guard_soft_delete on public.task_types;
create trigger task_types_guard_soft_delete
  before update of deleted_at on public.task_types
  for each row
  execute function private.guard_task_type_soft_delete();

create or replace function public.reassign_project_tasks_task_type(
  p_source_task_type_id uuid,
  p_target_task_type_id uuid,
  p_task_ids uuid[],
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_user_id uuid;
  v_company_id uuid;
  v_task_ids uuid[];
  v_request_payload jsonb;
  v_receipt_claimed boolean;
  v_receipt private.task_type_mutation_receipts%rowtype;
  v_source public.task_types%rowtype;
  v_target public.task_types%rowtype;
  v_task record;
  v_task_count integer := 0;
  v_now timestamptz := now();
  v_response jsonb;
begin
  v_actor_user_id := private.get_current_user_id();
  v_company_id := private.get_user_company_id();

  if v_actor_user_id is null or v_company_id is null then
    raise exception using
      message = 'task_type_actor_not_found',
      errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.users actor
    where actor.id = v_actor_user_id
      and actor.company_id = v_company_id
      and actor.deleted_at is null
      and coalesce(actor.is_active, false)
  ) then
    raise exception using
      message = 'task_type_actor_not_active',
      errcode = '42501';
  end if;

  if p_source_task_type_id is null
     or p_target_task_type_id is null
     or p_source_task_type_id = p_target_task_type_id
     or p_idempotency_key is null then
    raise exception using
      message = 'task_type_reassignment_invalid_request',
      errcode = '22023';
  end if;

  select coalesce(
    array_agg(distinct input.task_id order by input.task_id),
    array[]::uuid[]
  )
  into v_task_ids
  from unnest(coalesce(p_task_ids, array[]::uuid[])) input(task_id)
  where input.task_id is not null;

  if cardinality(v_task_ids) = 0 then
    raise exception using
      message = 'task_type_reassignment_empty_task_set',
      errcode = '22023';
  end if;

  v_request_payload := jsonb_build_object(
    'source_task_type_id', p_source_task_type_id,
    'target_task_type_id', p_target_task_type_id,
    'task_ids', to_jsonb(v_task_ids)
  );

  insert into private.task_type_mutation_receipts (
    company_id,
    idempotency_key,
    actor_user_id,
    operation,
    request_payload
  )
  values (
    v_company_id,
    p_idempotency_key,
    v_actor_user_id,
    'reassign',
    v_request_payload
  )
  on conflict (company_id, idempotency_key) do nothing
  returning true into v_receipt_claimed;

  if not coalesce(v_receipt_claimed, false) then
    if exists (
      select 1
      from private.task_type_mutation_receipts receipt
      where receipt.company_id = v_company_id
        and receipt.idempotency_key = p_idempotency_key
        and (
          receipt.actor_user_id is distinct from v_actor_user_id
          or receipt.operation is distinct from 'reassign'
          or receipt.request_payload is distinct from v_request_payload
        )
    ) then
      raise exception using
        message = 'task_type_idempotency_conflict',
        errcode = '22023';
    end if;

    select receipt.*
    into v_receipt
    from private.task_type_mutation_receipts receipt
    where receipt.company_id = v_company_id
      and receipt.idempotency_key = p_idempotency_key
    for update;

    if v_receipt.response is null then
      raise exception using
        message = 'task_type_mutation_incomplete',
        errcode = '40001';
    end if;

    return v_receipt.response;
  end if;

  perform task_type.id
  from public.task_types task_type
  where task_type.company_id = v_company_id
    and task_type.id in (
    p_source_task_type_id,
    p_target_task_type_id
  )
  order by task_type.id
  for update;

  select task_type.*
  into v_source
  from public.task_types task_type
  where task_type.id = p_source_task_type_id
    and task_type.company_id = v_company_id;

  select task_type.*
  into v_target
  from public.task_types task_type
  where task_type.id = p_target_task_type_id
    and task_type.company_id = v_company_id;

  if v_source.id is null
     or v_target.id is null
     or v_source.company_id is distinct from v_company_id
     or v_target.company_id is distinct from v_company_id
     or v_source.deleted_at is not null
     or v_target.deleted_at is not null then
    raise exception using
      message = 'task_type_source_or_target_invalid',
      errcode = '23503';
  end if;

  for v_task in
    select task.*
    from public.project_tasks task
    where task.id = any(v_task_ids)
      and task.company_id = v_company_id
      and task.task_type_id = p_source_task_type_id
      and task.deleted_at is null
    order by task.id
    for update
  loop
    v_task_count := v_task_count + 1;
  end loop;

  if v_task_count <> cardinality(v_task_ids) then
    raise exception using
      message = 'task_type_task_set_invalid',
      errcode = '23503';
  end if;

  if exists (
    select 1
    from public.project_tasks task
    where task.id = any(v_task_ids)
      and not coalesce(
        private.user_can_edit_task(v_actor_user_id, task.id),
        false
      )
  ) then
    raise exception using
      message = 'task_type_reassignment_forbidden',
      errcode = '42501';
  end if;

  update public.task_reminders reminder
  set deleted_at = v_now,
      updated_at = v_now
  from public.project_tasks task
  where reminder.task_id = task.id
    and reminder.company_id = v_company_id
    and task.id = any(v_task_ids)
    and task.company_id = v_company_id
    and task.status not in ('completed', 'cancelled')
    and reminder.source_template_id in (
      select source_template.id
      from public.task_type_reminders source_template
      where source_template.task_type_id = p_source_task_type_id
        and source_template.company_id = v_company_id
    )
    and reminder.acknowledged_at is null
    and reminder.dismissed_at is null
    and reminder.deleted_at is null;

  update public.project_tasks task
  set task_type_id = p_target_task_type_id,
      task_color = v_target.color,
      updated_at = v_now
  where task.id = any(v_task_ids)
    and task.company_id = v_company_id
    and task.deleted_at is null;

  insert into public.task_reminders (
    task_id,
    company_id,
    source_template_id,
    label,
    lead_time_days,
    fire_time_local,
    requires_ack,
    recipient_mode,
    recipient_config,
    fires_at
  )
  select
    task.id,
    task.company_id,
    target_template.id,
    target_template.label,
    target_template.lead_time_days,
    target_template.fire_time_local,
    target_template.requires_ack,
    target_template.recipient_mode,
    target_template.recipient_config,
    public.compute_reminder_fires_at(
      task.start_date,
      target_template.lead_time_days,
      target_template.fire_time_local,
      task.company_id
    )
  from public.project_tasks task
  cross join public.task_type_reminders target_template
  where task.id = any(v_task_ids)
    and task.company_id = v_company_id
    and task.deleted_at is null
    and task.status not in ('completed', 'cancelled')
    and target_template.task_type_id = p_target_task_type_id
    and target_template.company_id = v_company_id
    and target_template.deleted_at is null
    and not exists (
      select 1
      from public.task_reminders existing
      where existing.task_id = task.id
        and existing.source_template_id = target_template.id
        and existing.acknowledged_at is null
        and existing.dismissed_at is null
        and existing.deleted_at is null
    );

  v_response := jsonb_build_object(
    'operation', 'reassign',
    'source_task_type_id', p_source_task_type_id,
    'target_task_type_id', p_target_task_type_id,
    'task_count', v_task_count,
    'idempotency_key', p_idempotency_key
  );

  update private.task_type_mutation_receipts
  set response = v_response,
      completed_at = v_now
  where company_id = v_company_id
    and idempotency_key = p_idempotency_key;

  return v_response;
end;
$$;

create or replace function public.merge_task_type(
  p_source_task_type_id uuid,
  p_target_task_type_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_user_id uuid;
  v_company_id uuid;
  v_request_payload jsonb;
  v_receipt_claimed boolean;
  v_receipt private.task_type_mutation_receipts%rowtype;
  v_source public.task_types%rowtype;
  v_target public.task_types%rowtype;
  v_now timestamptz := now();
  v_tasks_moved integer := 0;
  v_recurrences_moved integer := 0;
  v_products_moved integer := 0;
  v_templates_moved integer := 0;
  v_response jsonb;
begin
  v_actor_user_id := private.get_current_user_id();
  v_company_id := private.get_user_company_id();

  if v_actor_user_id is null or v_company_id is null then
    raise exception using
      message = 'task_type_actor_not_found',
      errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.users actor
    where actor.id = v_actor_user_id
      and actor.company_id = v_company_id
      and actor.deleted_at is null
      and coalesce(actor.is_active, false)
  ) then
    raise exception using
      message = 'task_type_actor_not_active',
      errcode = '42501';
  end if;

  if not private.current_user_has_permission('tasks.edit', 'all')
     or not private.current_user_has_permission('tasks.delete', 'all') then
    raise exception using
      message = 'task_type_merge_forbidden',
      errcode = '42501';
  end if;

  if p_source_task_type_id is null
     or p_target_task_type_id is null
     or p_source_task_type_id = p_target_task_type_id
     or p_idempotency_key is null then
    raise exception using
      message = 'task_type_merge_invalid_request',
      errcode = '22023';
  end if;

  v_request_payload := jsonb_build_object(
    'source_task_type_id', p_source_task_type_id,
    'target_task_type_id', p_target_task_type_id
  );

  insert into private.task_type_mutation_receipts (
    company_id,
    idempotency_key,
    actor_user_id,
    operation,
    request_payload
  )
  values (
    v_company_id,
    p_idempotency_key,
    v_actor_user_id,
    'merge',
    v_request_payload
  )
  on conflict (company_id, idempotency_key) do nothing
  returning true into v_receipt_claimed;

  if not coalesce(v_receipt_claimed, false) then
    if exists (
      select 1
      from private.task_type_mutation_receipts receipt
      where receipt.company_id = v_company_id
        and receipt.idempotency_key = p_idempotency_key
        and (
          receipt.actor_user_id is distinct from v_actor_user_id
          or receipt.operation is distinct from 'merge'
          or receipt.request_payload is distinct from v_request_payload
        )
    ) then
      raise exception using
        message = 'task_type_idempotency_conflict',
        errcode = '22023';
    end if;

    select receipt.*
    into v_receipt
    from private.task_type_mutation_receipts receipt
    where receipt.company_id = v_company_id
      and receipt.idempotency_key = p_idempotency_key
    for update;

    if v_receipt.response is null then
      raise exception using
        message = 'task_type_mutation_incomplete',
        errcode = '40001';
    end if;

    return v_receipt.response;
  end if;

  -- Lock source, target, and every incoming dependency owner in one stable
  -- order. This makes concurrent merges serialize without cross-company locks.
  perform dependent.id
  from public.task_types dependent
  where dependent.company_id = v_company_id
    and (
      dependent.id in (
        p_source_task_type_id,
        p_target_task_type_id
      )
      or (
        dependent.id <> p_source_task_type_id
        and dependent.deleted_at is null
        and exists (
          select 1
          from jsonb_array_elements(
            case
              when jsonb_typeof(dependent.dependencies) = 'array'
                then dependent.dependencies
              else '[]'::jsonb
            end
          ) dependency
          where dependency ->> 'depends_on_task_type_id'
            = p_source_task_type_id::text
        )
      )
    )
  order by dependent.id
  for update;

  select task_type.*
  into v_source
  from public.task_types task_type
  where task_type.id = p_source_task_type_id
    and task_type.company_id = v_company_id;

  select task_type.*
  into v_target
  from public.task_types task_type
  where task_type.id = p_target_task_type_id
    and task_type.company_id = v_company_id;

  if v_source.id is null
     or v_target.id is null
     or v_source.company_id is distinct from v_company_id
     or v_target.company_id is distinct from v_company_id
     or v_source.deleted_at is not null
     or v_target.deleted_at is not null then
    raise exception using
      message = 'task_type_source_or_target_invalid',
      errcode = '23503';
  end if;

  if coalesce(v_source.is_default, false) then
    raise exception using
      message = 'default_task_type_delete_forbidden',
      errcode = '23514';
  end if;

  -- Lock every task whose type or per-task dependency overrides will change.
  perform task.id
  from public.project_tasks task
  where task.company_id = v_company_id
    and task.deleted_at is null
    and (
      task.task_type_id = p_source_task_type_id
      or exists (
        select 1
        from jsonb_array_elements(
          case
            when jsonb_typeof(task.dependency_overrides) = 'array'
              then task.dependency_overrides
            else '[]'::jsonb
          end
        ) dependency
        where dependency ->> 'depends_on_task_type_id'
          = p_source_task_type_id::text
      )
    )
  order by task.id
  for update;

  update public.task_reminders reminder
  set deleted_at = v_now,
      updated_at = v_now
  from public.project_tasks task
  where reminder.task_id = task.id
    and reminder.company_id = v_company_id
    and task.company_id = v_company_id
    and task.task_type_id = p_source_task_type_id
    and task.deleted_at is null
    and task.status not in ('completed', 'cancelled')
    and reminder.source_template_id in (
      select source_template.id
      from public.task_type_reminders source_template
      where source_template.task_type_id = p_source_task_type_id
        and source_template.company_id = v_company_id
    )
    and reminder.acknowledged_at is null
    and reminder.dismissed_at is null
    and reminder.deleted_at is null;

  insert into public.task_reminders (
    task_id,
    company_id,
    source_template_id,
    label,
    lead_time_days,
    fire_time_local,
    requires_ack,
    recipient_mode,
    recipient_config,
    fires_at
  )
  select
    task.id,
    task.company_id,
    target_template.id,
    target_template.label,
    target_template.lead_time_days,
    target_template.fire_time_local,
    target_template.requires_ack,
    target_template.recipient_mode,
    target_template.recipient_config,
    public.compute_reminder_fires_at(
      task.start_date,
      target_template.lead_time_days,
      target_template.fire_time_local,
      task.company_id
    )
  from public.project_tasks task
  cross join public.task_type_reminders target_template
  where task.company_id = v_company_id
    and task.task_type_id = p_source_task_type_id
    and task.deleted_at is null
    and task.status not in ('completed', 'cancelled')
    and target_template.task_type_id = p_target_task_type_id
    and target_template.company_id = v_company_id
    and target_template.deleted_at is null
    and not exists (
      select 1
      from public.task_reminders existing
      where existing.task_id = task.id
        and existing.source_template_id = target_template.id
        and existing.acknowledged_at is null
        and existing.dismissed_at is null
        and existing.deleted_at is null
    );

  update public.project_tasks task
  set task_type_id = p_target_task_type_id,
      task_color = v_target.color,
      updated_at = v_now
  where task.company_id = v_company_id
    and task.task_type_id = p_source_task_type_id
    and task.deleted_at is null;
  get diagnostics v_tasks_moved = row_count;

  update public.task_recurrences recurrence
  set task_type_id = p_target_task_type_id,
      updated_at = v_now
  where recurrence.company_id = v_company_id
    and recurrence.task_type_id = p_source_task_type_id
    and recurrence.deleted_at is null;
  get diagnostics v_recurrences_moved = row_count;

  update public.products product
  set task_type_ref = p_target_task_type_id,
      task_type_id = p_target_task_type_id::text,
      updated_at = v_now
  where product.company_id = v_company_id
    and product.deleted_at is null
    and (
      product.task_type_ref = p_source_task_type_id
      or product.task_type_id = p_source_task_type_id::text
      or (
        v_source.bubble_id is not null
        and product.task_type_id = v_source.bubble_id
      )
    );
  get diagnostics v_products_moved = row_count;

  update public.task_templates template
  set task_type_ref = p_target_task_type_id,
      task_type_id = p_target_task_type_id::text,
      updated_at = v_now
  where template.company_id = v_company_id::text
    and template.deleted_at is null
    and (
      template.task_type_ref = p_source_task_type_id
      or template.task_type_id = p_source_task_type_id::text
      or (
        v_source.bubble_id is not null
        and template.task_type_id = v_source.bubble_id
      )
    );
  get diagnostics v_templates_moved = row_count;

  with expanded as (
    select
      task.id as task_id,
      dependency.value as original_dependency,
      dependency.ordinality as original_ordinality,
      case
        when dependency.value ->> 'depends_on_task_type_id'
          = p_source_task_type_id::text
          then jsonb_set(
            dependency.value,
            '{depends_on_task_type_id}',
            to_jsonb(p_target_task_type_id::text),
            false
          )
        else dependency.value
      end as rewritten_dependency
    from public.project_tasks task
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(task.dependency_overrides) = 'array'
          then task.dependency_overrides
        else '[]'::jsonb
      end
    ) with ordinality dependency(value, ordinality)
    where task.company_id = v_company_id
      and task.deleted_at is null
  ),
  affected as (
    select distinct expanded.task_id
    from expanded
    where expanded.original_dependency ->> 'depends_on_task_type_id'
      = p_source_task_type_id::text
  ),
  normalized as (
    select
      expanded.task_id,
      expanded.original_dependency,
      expanded.original_ordinality,
      expanded.rewritten_dependency,
      expanded.rewritten_dependency ->> 'depends_on_task_type_id'
        as depends_on_task_type_id
    from expanded
    join affected
      on affected.task_id = expanded.task_id
  ),
  ranked as (
    select
      normalized.*,
      row_number() over (
        partition by
          normalized.task_id,
          coalesce(
            normalized.depends_on_task_type_id,
            '__unkeyed__' || normalized.original_ordinality::text
          )
        order by
          case
            when normalized.original_dependency
              ->> 'depends_on_task_type_id'
              = p_target_task_type_id::text then 0
            when normalized.original_dependency
              ->> 'depends_on_task_type_id'
              = p_source_task_type_id::text then 1
            else 2
          end,
          normalized.original_ordinality
      ) as preference_rank
    from normalized
  ),
  rebuilt as (
    select
      ranked.task_id,
      jsonb_agg(
        ranked.rewritten_dependency
        order by ranked.original_ordinality
      ) as dependencies
    from ranked
    join public.project_tasks task
      on task.id = ranked.task_id
     and task.company_id = v_company_id
    where ranked.preference_rank = 1
      and (
        ranked.depends_on_task_type_id is null
        or task.task_type_id is null
        or ranked.depends_on_task_type_id <> task.task_type_id::text
      )
    group by ranked.task_id
  )
  update public.project_tasks task
  set dependency_overrides = coalesce(rebuilt.dependencies, '[]'::jsonb),
      updated_at = v_now
  from affected
  left join rebuilt
    on rebuilt.task_id = affected.task_id
  where task.id = affected.task_id
    and task.company_id = v_company_id;

  with expanded as (
    select
      dependent.id as dependent_id,
      dependency.value as original_dependency,
      dependency.ordinality as original_ordinality,
      case
        when dependency.value ->> 'depends_on_task_type_id'
          = p_source_task_type_id::text
          then jsonb_set(
            dependency.value,
            '{depends_on_task_type_id}',
            to_jsonb(p_target_task_type_id::text),
            false
          )
        else dependency.value
      end as rewritten_dependency
    from public.task_types dependent
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(dependent.dependencies) = 'array'
          then dependent.dependencies
        else '[]'::jsonb
      end
    ) with ordinality dependency(value, ordinality)
    where dependent.company_id = v_company_id
      and dependent.id <> p_source_task_type_id
      and dependent.deleted_at is null
  ),
  affected as (
    select distinct expanded.dependent_id
    from expanded
    where expanded.original_dependency ->> 'depends_on_task_type_id'
      = p_source_task_type_id::text
  ),
  normalized as (
    select
      expanded.dependent_id,
      expanded.original_dependency,
      expanded.original_ordinality,
      expanded.rewritten_dependency,
      expanded.rewritten_dependency ->> 'depends_on_task_type_id'
        as depends_on_task_type_id
    from expanded
    join affected
      on affected.dependent_id = expanded.dependent_id
  ),
  ranked as (
    select
      normalized.*,
      row_number() over (
        partition by
          normalized.dependent_id,
          coalesce(
            normalized.depends_on_task_type_id,
            '__unkeyed__' || normalized.original_ordinality::text
          )
        order by
          case
            when normalized.original_dependency
              ->> 'depends_on_task_type_id'
              = p_target_task_type_id::text then 0
            when normalized.original_dependency
              ->> 'depends_on_task_type_id'
              = p_source_task_type_id::text then 1
            else 2
          end,
          normalized.original_ordinality
      ) as preference_rank
    from normalized
  ),
  rebuilt as (
    select
      ranked.dependent_id,
      jsonb_agg(
        ranked.rewritten_dependency
        order by ranked.original_ordinality
      ) as dependencies
    from ranked
    join public.task_types dependent
      on dependent.id = ranked.dependent_id
     and dependent.company_id = v_company_id
    where ranked.preference_rank = 1
      and (
        ranked.depends_on_task_type_id is null
        or ranked.depends_on_task_type_id <> dependent.id::text
      )
    group by ranked.dependent_id
  )
  update public.task_types dependent
  set dependencies = coalesce(rebuilt.dependencies, '[]'::jsonb),
      updated_at = v_now
  from affected
  left join rebuilt
    on rebuilt.dependent_id = affected.dependent_id
  where dependent.id = affected.dependent_id
    and dependent.company_id = v_company_id;

  update public.task_type_reminders source_template
  set deleted_at = v_now,
      updated_at = v_now
  where source_template.company_id = v_company_id
    and source_template.task_type_id = p_source_task_type_id
    and source_template.deleted_at is null;

  update public.task_types source
  set deleted_at = v_now,
      updated_at = v_now
  where source.id = p_source_task_type_id
    and source.company_id = v_company_id
    and source.deleted_at is null;

  if not found then
    raise exception using
      message = 'task_type_merge_source_delete_failed',
      errcode = '40001';
  end if;

  v_response := jsonb_build_object(
    'operation', 'merge',
    'source_task_type_id', p_source_task_type_id,
    'target_task_type_id', p_target_task_type_id,
    'task_count', v_tasks_moved,
    'recurrence_count', v_recurrences_moved,
    'product_count', v_products_moved,
    'template_count', v_templates_moved,
    'idempotency_key', p_idempotency_key
  );

  update private.task_type_mutation_receipts
  set response = v_response,
      completed_at = v_now
  where company_id = v_company_id
    and idempotency_key = p_idempotency_key;

  return v_response;
end;
$$;

revoke all on function public.reassign_project_tasks_task_type(uuid, uuid, uuid[], uuid) from public;
grant execute on function public.reassign_project_tasks_task_type(uuid, uuid, uuid[], uuid) to anon, authenticated, service_role;

revoke all on function public.merge_task_type(uuid, uuid, uuid) from public;
grant execute on function public.merge_task_type(uuid, uuid, uuid) to anon, authenticated, service_role;

