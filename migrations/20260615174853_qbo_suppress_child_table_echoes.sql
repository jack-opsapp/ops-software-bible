do $$
declare
  v_def text;
  v_new text;
begin
  select pg_get_functiondef('public.enqueue_accounting_sync()'::regprocedure) into v_def;
  v_new := replace(
    v_def,
    'if tg_table_name not in (''sub_clients'', ''line_items'') and exists (',
    'if exists ('
  );
  if v_new = v_def then
    raise exception 'qbo_suppress_child_table_echoes: suppression-skip guard not found (already patched or drifted)';
  end if;
  execute v_new;
end $$;

do $$
declare
  v_def text;
begin
  select pg_get_functiondef('public.enqueue_accounting_sync()'::regprocedure) into v_def;
  if v_def ilike '%not in (''sub_clients'', ''line_items'') and exists%' then
    raise exception 'qbo_suppress_child_table_echoes_sentinel: child-table suppression skip still present';
  end if;
  if v_def not ilike '%from public.accounting_sync_suppressions s%' then
    raise exception 'qbo_suppress_child_table_echoes_sentinel: suppression check missing';
  end if;
  if v_def not ilike '%when ''sub_clients'' then nullif(v_row_json->>''client_id'', '''')::uuid%' then
    raise exception 'qbo_suppress_child_table_echoes_sentinel: sub_clients parent-id resolution changed unexpectedly';
  end if;
end $$;

revoke all on function public.enqueue_accounting_sync() from public, anon, authenticated;
grant execute on function public.enqueue_accounting_sync() to service_role;
