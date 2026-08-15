-- W3 security posture sweep — fix `rls_policy_always_true` exposures on the three
-- ops-web-owned tables where an always-true predicate is a real exposure (not
-- intentional write-only public ingestion). See
-- ops-web/docs/artifacts/w3-security-posture-disposition-2026-07-03.md.

begin;

set local search_path = public, private, pg_temp;

-- 1. qa_bugs — operator-only (drops the anon full-CRUD policy).
drop policy if exists "Service role full access" on public.qa_bugs;
create policy "qa_bugs_ops_admin_all" on public.qa_bugs
  for all
  to public
  using (private.is_ops_admin())
  with check (private.is_ops_admin());

-- 2. beta_access_requests — caller reads only their own requests.
drop policy if exists "beta_requests_select" on public.beta_access_requests;
create policy "beta_requests_select_own" on public.beta_access_requests
  for select
  to public
  using (user_id = private.get_current_user_id()::text);

-- 3. duplicate_reviews — INSERT constrained to the caller's own company.
drop policy if exists "Service role can insert" on public.duplicate_reviews;
create policy "duplicate_reviews_insert_company" on public.duplicate_reviews
  for insert
  to public
  with check (
    company_id in (
      select users.company_id from users where users.id = private.get_current_user_id()
    )
  );

-- Sentinel: originals gone, replacements present, none bare-true.
do $do$
declare
  v_old int;
  v_new int;
  v_true int;
begin
  select count(*) into v_old
  from pg_policies
  where schemaname = 'public' and (
       (tablename = 'qa_bugs'              and policyname = 'Service role full access')
    or (tablename = 'beta_access_requests' and policyname = 'beta_requests_select')
    or (tablename = 'duplicate_reviews'    and policyname = 'Service role can insert')
  );
  if v_old <> 0 then
    raise exception 'sec_w3_always_true_sentinel: % original always-true policy(ies) still present', v_old;
  end if;

  select count(*) into v_new
  from pg_policies
  where schemaname = 'public' and (
       (tablename = 'qa_bugs'              and policyname = 'qa_bugs_ops_admin_all')
    or (tablename = 'beta_access_requests' and policyname = 'beta_requests_select_own')
    or (tablename = 'duplicate_reviews'    and policyname = 'duplicate_reviews_insert_company')
  );
  if v_new <> 3 then
    raise exception 'sec_w3_always_true_sentinel: expected 3 replacement policies, found %', v_new;
  end if;

  select count(*) into v_true
  from pg_policies
  where schemaname = 'public'
    and tablename in ('qa_bugs','beta_access_requests','duplicate_reviews')
    and policyname in ('qa_bugs_ops_admin_all','beta_requests_select_own','duplicate_reviews_insert_company')
    and (coalesce(qual,'') = 'true' or coalesce(with_check,'') = 'true');
  if v_true <> 0 then
    raise exception 'sec_w3_always_true_sentinel: % replacement policy(ies) still evaluate to true', v_true;
  end if;
end
$do$;

commit;
