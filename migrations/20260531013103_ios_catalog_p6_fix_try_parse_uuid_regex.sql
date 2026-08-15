create or replace function private.try_parse_uuid(p_value text)
  returns uuid
  language plpgsql
  immutable
  set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if p_value is null then
    return null;
  end if;

  if btrim(p_value) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return btrim(p_value)::uuid;
  end if;

  return null;
end;
$function$;

do $$
begin
  if private.try_parse_uuid('00000000-0000-4000-8000-000000000000') is null then
    raise exception 'try_parse_uuid regression: rejected a valid uuid';
  end if;
  if private.try_parse_uuid('not-a-uuid') is not null then
    raise exception 'try_parse_uuid regression: accepted a non-uuid';
  end if;
end;
$$;
