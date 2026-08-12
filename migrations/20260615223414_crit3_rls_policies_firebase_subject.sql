-- RLS policies: resolve the actor via the Firebase-safe identity scheme instead
-- of auth.uid(). See 20260615230000_crit3_rls_policies_firebase_subject.sql.
-- Six policies on task_recurrences, task_recurrence_exceptions, duplicate_reviews,
-- data_setup_requests evaluated auth.uid() (sub::uuid) and raised 22P02 for
-- Firebase-subject clients, aborting queries on those (RLS-on, anon/authenticated)
-- tables. Swap auth.uid() -> private.get_current_user_id() and (auth.uid())::text
-- -> (auth.jwt()->>'sub'). Company-isolation semantics unchanged. Sentinel-guarded.

begin;

set local search_path = public, private, pg_temp;

-- 1. task_recurrences (ALL)
alter policy task_recurrences_company_isolation on public.task_recurrences
  using (
    company_id in (
      select users.company_id from users where users.id = private.get_current_user_id()
    )
  );

-- 2. task_recurrence_exceptions (ALL)
alter policy task_recurrence_exceptions_company_isolation on public.task_recurrence_exceptions
  using (
    recurrence_id in (
      select task_recurrences.id from task_recurrences
      where task_recurrences.company_id in (
        select users.company_id from users where users.id = private.get_current_user_id()
      )
    )
  );

-- 3. duplicate_reviews (SELECT)
alter policy "Users can view own company reviews" on public.duplicate_reviews
  using (
    company_id in (
      select users.company_id from users where users.id = private.get_current_user_id()
    )
  );

-- 4. duplicate_reviews (UPDATE)
alter policy "Users can update own company reviews" on public.duplicate_reviews
  using (
    company_id in (
      select users.company_id from users where users.id = private.get_current_user_id()
    )
  );

-- 5. data_setup_requests (INSERT)
alter policy data_setup_requests_insert_company on public.data_setup_requests
  with check (
    company_id = (select private.get_user_company_id())
    and requested_by in (
      select users.id from users
      where users.auth_id = (auth.jwt() ->> 'sub')
         or users.firebase_uid = (auth.jwt() ->> 'sub')
    )
  );

-- 6. data_setup_requests (admin UPDATE)
alter policy data_setup_requests_update_admin on public.data_setup_requests
  using (
    company_id = (select private.get_user_company_id())
    and exists (
      select 1 from users u
      where (u.auth_id = (auth.jwt() ->> 'sub') or u.firebase_uid = (auth.jwt() ->> 'sub'))
        and u.company_id = data_setup_requests.company_id
        and u.is_company_admin = true
    )
  )
  with check (
    company_id = (select private.get_user_company_id())
    and exists (
      select 1 from users u
      where (u.auth_id = (auth.jwt() ->> 'sub') or u.firebase_uid = (auth.jwt() ->> 'sub'))
        and u.company_id = data_setup_requests.company_id
        and u.is_company_admin = true
    )
  );

-- Sentinel: none of the six target policies may reference the uid() builtin now.
do $do$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from pg_policies
  where schemaname = 'public'
    and (schemaname, tablename, policyname) in (
      ('public','task_recurrences','task_recurrences_company_isolation'),
      ('public','task_recurrence_exceptions','task_recurrence_exceptions_company_isolation'),
      ('public','duplicate_reviews','Users can view own company reviews'),
      ('public','duplicate_reviews','Users can update own company reviews'),
      ('public','data_setup_requests','data_setup_requests_insert_company'),
      ('public','data_setup_requests','data_setup_requests_update_admin')
    )
    and (coalesce(qual, '') ~ 'auth\.uid\(\)' or coalesce(with_check, '') ~ 'auth\.uid\(\)');

  if v_bad > 0 then
    raise exception 'crit3_rls_subject_sentinel: % target policy expression(s) still call the uid() builtin', v_bad;
  end if;
end
$do$;

commit;
