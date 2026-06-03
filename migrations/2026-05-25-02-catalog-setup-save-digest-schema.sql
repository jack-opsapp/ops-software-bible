-- Repair catalog_setup_save request hashing after the original function was
-- deployed with a tight search_path that excludes the extensions schema.

begin;

do $$
declare
  v_definition text;
  v_expected text := 'encode(digest(convert_to(p_payload::text, ''utf8''), ''sha256''), ''hex'')';
  v_replacement text := 'encode(extensions.digest(convert_to(p_payload::text, ''utf8''), ''sha256''), ''hex'')';
  v_occurrences integer;
begin
  select pg_get_functiondef('public.catalog_setup_save(uuid,text,jsonb)'::regprocedure)
    into v_definition;

  if v_definition is null then
    raise exception 'public.catalog_setup_save(uuid,text,jsonb) was not found';
  end if;

  v_occurrences := (
    length(v_definition) - length(replace(v_definition, v_expected, ''))
  ) / length(v_expected);

  if v_occurrences <> 1 then
    raise exception 'Expected exactly one unqualified digest call in public.catalog_setup_save(uuid,text,jsonb), found %',
      v_occurrences;
  end if;

  v_definition := replace(v_definition, v_expected, v_replacement);

  if position(v_replacement in v_definition) = 0 then
    raise exception 'Failed to qualify digest call in public.catalog_setup_save(uuid,text,jsonb)';
  end if;

  execute v_definition;
end;
$$;

commit;
