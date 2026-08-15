-- The tenant-integrity trigger recomputed the canonical content hash with
-- chr(0), which PostgreSQL refuses outright ("null character not permitted").
-- Every INSERT/UPDATE on email_signatures has therefore failed since the
-- trigger shipped — no signature could ever be saved. The app hashes
-- sha256(utf8(html) || 0x00 || utf8(text)); bytea concatenation reproduces
-- those exact bytes without ever constructing a NUL *text* value.
-- Equivalence proven: sha256('a'||0x00||'b') = 59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138
-- from both the app-side algorithm and this expression.
CREATE OR REPLACE FUNCTION private.enforce_email_signature_tenant_integrity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_connection public.email_connections%rowtype;
  v_expected_content_hash text;
begin
  select c.*
  into v_connection
  from public.email_connections c
  where c.id = new.connection_id
  for share;

  if v_connection.id is null
    or v_connection.company_id <> new.company_id::text
  then
    raise exception 'email signature connection does not belong to company';
  end if;

  if new.scope_user_id is not null and not exists (
    select 1
    from public.users u
    where u.id = new.scope_user_id
      and u.company_id = new.company_id
  ) then
    raise exception 'email signature scope user does not belong to company';
  end if;

  if v_connection.type = 'individual' and (
    nullif(btrim(v_connection.user_id), '') is null
    or new.scope_user_id is null
    or new.scope_user_id::text <> btrim(v_connection.user_id)
  ) then
    raise exception 'email signature scope user does not own individual connection';
  end if;

  if new.created_by is not null and not exists (
    select 1
    from public.users u
    where u.id = new.created_by
      and u.company_id = new.company_id
  ) then
    raise exception 'email signature creator does not belong to company';
  end if;

  if new.updated_by is not null and not exists (
    select 1
    from public.users u
    where u.id = new.updated_by
      and u.company_id = new.company_id
  ) then
    raise exception 'email signature updater does not belong to company';
  end if;

  if not private.email_signature_content_is_safe(
    new.content_html,
    new.content_text
  ) then
    raise exception 'email signature content contains unsafe markup';
  end if;

  v_expected_content_hash := encode(
    extensions.digest(
      convert_to(coalesce(new.content_html, ''), 'UTF8')
        || '\x00'::bytea
        || convert_to(coalesce(new.content_text, ''), 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  if new.content_hash is distinct from v_expected_content_hash then
    raise exception 'email signature content hash does not match canonical content';
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
    new.updated_at := now();
  else
    new.created_at := old.created_at;
    new.updated_at := now();
  end if;

  return new;
end;
$function$;
