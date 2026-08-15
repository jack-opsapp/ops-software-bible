-- Bug a2af6e8a: an opportunity converting to a project (customer approval via
-- email/AI, web manual, or iOS) produced NO in-app notification — the operator
-- only learned via an external customer email. convert_opportunity_to_project
-- inserts exactly one 'converted_to_project' disposition per conversion (the
-- already_converted guard prevents repeats), so an AFTER trigger on that row
-- is the single, canonical dispatch point covering every conversion path.
--
-- Recipients: the company's owner (account_holder) + admins, excluding whoever
-- decided it (a manual in-app converter doesn't need to be told what they just
-- did). Fully exception-safe: notification dispatch must NEVER block a
-- conversion, so any error is swallowed and the conversion proceeds.
--
-- iOS consumes type='lead_converted' + project_id (see NotificationListView
-- routing); web consumes the /dashboard?openProject action_url.
create or replace function private.notify_lead_conversion()
returns trigger
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $function$
declare
  v_company public.companies%rowtype;
  v_contact text;
  v_project_title text;
  v_body text;
  v_action_url text;
  v_uid text;
begin
  if NEW.converted_project_ref is null then
    return NEW;
  end if;

  select * into v_company from public.companies where id = NEW.company_id;
  if not found then
    return NEW;
  end if;

  select nullif(btrim(coalesce(o.contact_name, '')), '')
    into v_contact
    from public.opportunities o
   where o.id = NEW.opportunity_id;

  select coalesce(nullif(btrim(p.title), ''), 'New project')
    into v_project_title
    from public.projects p
   where p.id = NEW.converted_project_ref;
  v_project_title := coalesce(v_project_title, 'New project');

  v_body := case when v_contact is not null then v_contact || ' approved. ' else '' end
            || 'New project: ' || v_project_title;
  v_action_url := '/dashboard?openProject=' || NEW.converted_project_ref::text || '&mode=view';

  for v_uid in
    select u.id::text
      from public.users u
     where u.company_id = NEW.company_id
       and coalesce(u.is_active, true) is true
       and u.deleted_at is null
       and (
         u.id::text = v_company.account_holder_id
         or u.id::text = any(coalesce(v_company.admin_ids, array[]::text[]))
       )
       and (NEW.decided_by is null or u.id <> NEW.decided_by)
  loop
    perform public.create_notification_if_new(
      p_user_id        => v_uid,
      p_company_id     => NEW.company_id::text,
      p_type           => 'lead_converted',
      p_title          => 'LEAD WON',
      p_body           => v_body,
      p_persistent     => false,
      p_action_url     => v_action_url,
      p_action_label   => 'OPEN PROJECT',
      p_project_id     => NEW.converted_project_ref::text,
      p_deep_link_type => null
    );
  end loop;

  return NEW;
exception
  when others then
    -- Never let notification dispatch block a conversion.
    return NEW;
end;
$function$;

drop trigger if exists trg_notify_lead_conversion on public.opportunity_dispositions;
create trigger trg_notify_lead_conversion
  after insert on public.opportunity_dispositions
  for each row
  when (NEW.disposition = 'converted_to_project')
  execute function private.notify_lead_conversion();
