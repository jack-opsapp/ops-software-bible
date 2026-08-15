drop function if exists public.create_notification_if_new(text, text, text, text, text, boolean, text, text, text);

create or replace function public.create_notification_if_new(
  p_user_id text,
  p_company_id text,
  p_type text,
  p_title text,
  p_body text,
  p_persistent boolean default false,
  p_action_url text default null,
  p_action_label text default null,
  p_project_id text default null,
  p_deep_link_type text default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.notifications (
    user_id,
    company_id,
    type,
    title,
    body,
    is_read,
    persistent,
    action_url,
    action_label,
    project_id,
    deep_link_type
  )
  values (
    p_user_id,
    p_company_id,
    p_type,
    p_title,
    p_body,
    false,
    p_persistent,
    p_action_url,
    p_action_label,
    p_project_id,
    p_deep_link_type
  )
  on conflict do nothing;
end;
$$;

grant execute on function public.create_notification_if_new(
  text, text, text, text, text, boolean, text, text, text, text
) to anon, authenticated, service_role;

do $$
declare
  v_reg regprocedure;
  v_functiondef text;
begin
  v_reg := to_regprocedure(
    'public.create_notification_if_new(text, text, text, text, text, boolean, text, text, text, text)'
  );
  if v_reg is null then
    raise exception 'create_notification_if_new_deep_link_sentinel: 10-arg create_notification_if_new is missing';
  end if;

  v_functiondef := pg_get_functiondef(v_reg);

  if v_functiondef !~ '[^_]deep_link_type' then
    raise exception 'create_notification_if_new_deep_link_sentinel: insert does not write the deep_link_type column';
  end if;

  if v_functiondef not ilike '%on conflict do nothing%' then
    raise exception 'create_notification_if_new_deep_link_sentinel: create_notification_if_new lost conflict-do-nothing dedup';
  end if;
end $$;
