-- The company branch aliased public.users AS user_row while a plpgsql variable
-- of the same name (user_row public.users%rowtype) was already in scope, so
-- `user_row.id` could not be resolved -> 42702 "column reference user_row.id is
-- ambiguous". The trigger therefore threw on every attempt to record a
-- reconciliation-required provider mutation, which (a) failed the
-- mark_email_provider_mutation_reconciliation_required RPC, permanently
-- quarantining mailbox draft placement, and (b) suppressed the very
-- "Draft placement needs review" notification this trigger exists to raise.
-- Only the alias is renamed; every other statement is unchanged.
CREATE OR REPLACE FUNCTION private.notify_email_provider_mutation_reconciliation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  user_row public.users%rowtype;
  v_dedupe_key text := 'email-provider-mutation-reconciliation:' || new.id::text;
  v_title text;
  v_body text;
  v_action_url text;
  v_action_label text;
begin
  if new.status = 'completed' and old.status <> 'completed' then
    update public.notifications notification
    set resolved_at = clock_timestamp(),
        is_read = true
    where notification.company_id = new.company_id::text
      and notification.type = 'system'
      and notification.dedupe_key = v_dedupe_key
      and notification.resolved_at is null;
    return new;
  end if;

  if new.status <> 'reconciliation_required'
     or old.status = 'reconciliation_required' then
    return new;
  end if;

  if new.operation_kind = 'draft_create' then
    v_title := 'Draft placement needs review';
    v_body := 'OPS could not confirm one mailbox draft. Check Drafts before creating another.';
  else
    v_title := 'Email connection needs review';
    v_body := 'OPS could not confirm this mailbox update. Review the connection before retrying.';
  end if;

  if new.connection_type_snapshot = 'individual' then
    select active_user.* into user_row
    from public.users active_user
    where active_user.id = new.owner_user_id_snapshot
      and active_user.company_id = new.company_id
      and active_user.deleted_at is null
      and coalesce(active_user.is_active, false)
    limit 1;
    if not found then
      return new;
    end if;
    v_action_url := null;
    v_action_label := null;
    insert into public.notifications (
      user_id, company_id, type, title, body, is_read, persistent,
      action_url, action_label, dedupe_key
    ) values (
      user_row.id::text, new.company_id::text, 'system', v_title, v_body,
      false, true, v_action_url, v_action_label, v_dedupe_key
    ) on conflict do nothing;
    return new;
  end if;

  if new.connection_type_snapshot = 'company' then
    v_action_url := '/settings?tab=integrations';
    v_action_label := 'Review mailbox';
    insert into public.notifications (
      user_id, company_id, type, title, body, is_read, persistent,
      action_url, action_label, dedupe_key
    )
    select
      recipient.id::text,
      new.company_id::text,
      'system',
      v_title,
      v_body,
      false,
      true,
      v_action_url,
      v_action_label,
      v_dedupe_key
    from public.users recipient
    where recipient.company_id = new.company_id
      and recipient.deleted_at is null
      and coalesce(recipient.is_active, false)
      and public.has_permission(
        recipient.id,
        'settings.integrations',
        'all'
      )
    on conflict do nothing;
  end if;
  return new;
end;
$function$;
