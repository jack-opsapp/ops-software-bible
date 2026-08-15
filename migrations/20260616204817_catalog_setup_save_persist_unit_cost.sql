-- Persist products.unit_cost in catalog_setup_save (P6-6).
-- The RPC dropped unit_cost: absent from the products INSERT column list/VALUES and
-- from BOTH ON CONFLICT (id) DO UPDATE clauses (create-mode + edit-mode blocks).
-- This adds unit_cost additively, mirroring minimum_charge's "case … else null end"
-- (NULL when absent, so an explicit 0 is still written but omission is preserved),
-- and uses coalesce(excluded.unit_cost, public.products.unit_cost) in the UPDATE so a
-- conflict-update that omits cost (web merge docs; iOS Advanced "edit" sends no cost)
-- can never wipe an existing cost. Body-only; no signature/return change (iOS-safe).
--
-- Applied programmatically off the live pg_get_functiondef so the 6380-line body is
-- never hand-retyped. Drift guards abort (rolling back) if the function shape differs
-- from what was recon'd. Idempotent: no-op if unit_cost already present.
do $mig$
declare
  v_src text;
  v_lines text[];
  v_out text[] := array[]::text[];
  v_line text;
  v_trim text;
  v_indent text;
  c_collist int := 0;
  c_values  int := 0;
  c_set     int := 0;
  v_when    text := $q$when coalesce(v_product_doc->>'unit_cost', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then (v_product_doc->>'unit_cost')::numeric$q$;
  v_setline text := $q$unit_cost = coalesce(excluded.unit_cost, public.products.unit_cost),$q$;
  v_pu_anchor text := $q$coalesce(nullif(btrim(v_product_doc->>'pricing_unit'), ''), 'each'),$q$;
  v_new   text;
  v_added int;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'catalog_setup_save';

  if v_src is null then
    raise exception 'catalog_setup_save not found — aborting';
  end if;

  if position('unit_cost' in v_src) > 0 then
    raise notice 'catalog_setup_save already references unit_cost — skipping (already migrated)';
    return;
  end if;

  v_lines := string_to_array(v_src, E'\n');

  foreach v_line in array v_lines loop
    v_trim   := btrim(v_line);
    v_indent := substring(v_line from '^[ ]*');

    -- VALUES: insert the unit_cost case immediately BEFORE the pricing_unit value line
    if v_trim = v_pu_anchor then
      v_out := array_append(v_out, v_indent || 'case');
      v_out := array_append(v_out, v_indent || '  ' || v_when);
      v_out := array_append(v_out, v_indent || '  else null');
      v_out := array_append(v_out, v_indent || 'end,');
      c_values := c_values + 1;
    end if;

    v_out := array_append(v_out, v_line);

    -- COLUMN LIST: after the bare `base_price,` entry
    if v_trim = 'base_price,' then
      v_out := array_append(v_out, v_indent || 'unit_cost,');
      c_collist := c_collist + 1;
    -- SET clause: after `base_price = excluded.base_price,`
    elsif v_trim = 'base_price = excluded.base_price,' then
      v_out := array_append(v_out, v_indent || v_setline);
      c_set := c_set + 1;
    end if;
  end loop;

  if c_collist <> 2 or c_values <> 2 or c_set <> 2 then
    raise exception 'anchor count mismatch (collist=%, values=%, set=%) — function drifted, aborting',
      c_collist, c_values, c_set;
  end if;

  v_added := array_length(v_out, 1) - array_length(v_lines, 1);
  if v_added <> 12 then
    raise exception 'unexpected added-line count % (expected 12) — aborting', v_added;
  end if;

  v_new := array_to_string(v_out, E'\n');

  execute v_new;
end
$mig$;
