begin;

-- Replace PARTIAL (company_id, qb_id) unique indexes with FULL unique indexes
-- so PostgREST `.upsert({onConflict:"company_id,qb_id"})` (which omits the
-- partial predicate) has a valid ON CONFLICT arbiter. NULLs are DISTINCT by
-- default, so unlimited non-QB rows (qb_id IS NULL) per company still coexist.
-- The partial index already guaranteed non-null uniqueness, so no collision is
-- possible on the full index. Index-only (iOS-safe). Sentinel verifies each is
-- unique AND non-partial (indpred IS NULL).

drop index if exists public.clients_company_qb_id_uniq;
create unique index clients_company_qb_id_uniq on public.clients (company_id, qb_id);

drop index if exists public.sub_clients_company_qb_id_uniq;
create unique index sub_clients_company_qb_id_uniq on public.sub_clients (company_id, qb_id);

drop index if exists public.invoices_company_qb_id_uniq;
create unique index invoices_company_qb_id_uniq on public.invoices (company_id, qb_id);

drop index if exists public.estimates_company_qb_id_uniq;
create unique index estimates_company_qb_id_uniq on public.estimates (company_id, qb_id);

drop index if exists public.payments_company_qb_id_uniq;
create unique index payments_company_qb_id_uniq on public.payments (company_id, qb_id);

do $$
declare
  v_idx text;
begin
  foreach v_idx in array array[
    'clients_company_qb_id_uniq','sub_clients_company_qb_id_uniq',
    'invoices_company_qb_id_uniq','estimates_company_qb_id_uniq','payments_company_qb_id_uniq'
  ]
  loop
    if not exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_index i on i.indexrelid = c.oid
      where n.nspname='public' and c.relname=v_idx
        and c.relkind='i' and i.indisunique and i.indpred is null
    ) then
      raise exception 'qbo_full_uniq_sentinel: % is missing, non-unique, or still partial', v_idx;
    end if;
  end loop;
end $$;

commit;
