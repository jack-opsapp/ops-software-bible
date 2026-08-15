do $repair$
declare
  v_ext_schema text;
  v_target regprocedure;
  v_def text;
  v_new_def text;
  v_repaired int := 0;
begin
  select n.nspname
    into v_ext_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'vector';

  if v_ext_schema is null then
    raise exception
      'pgvector (extension "vector") is not installed; cannot repair embedding cast';
  end if;

  if v_ext_schema = 'extensions' then
    raise notice
      'pgvector already resides in "extensions"; embedding casts need no repair';
    return;
  end if;

  for v_target in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) like '%extensions.vector%'
    order by 1
  loop
    v_def := pg_get_functiondef(v_target);
    v_new_def := replace(
      v_def,
      'extensions.vector(',
      quote_ident(v_ext_schema) || '.vector('
    );

    if v_new_def = v_def then
      continue;
    end if;

    execute v_new_def;
    v_repaired := v_repaired + 1;
    raise notice 'repaired embedding cast in %', v_target;
  end loop;

  if v_repaired = 0 then
    raise notice 'no hardcoded extensions.vector casts found; nothing repaired';
  end if;
end
$repair$;

do $verify$
declare
  v_remaining text;
begin
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_remaining
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
    and pg_get_functiondef(p.oid) like '%extensions.vector%'
    and not exists (
      select 1
      from pg_extension e
      join pg_namespace en on en.oid = e.extnamespace
      where e.extname = 'vector' and en.nspname = 'extensions'
    );

  if v_remaining is not null then
    raise exception
      'embedding cast repair incomplete; still references extensions.vector in: %',
      v_remaining;
  end if;
end
$verify$;
