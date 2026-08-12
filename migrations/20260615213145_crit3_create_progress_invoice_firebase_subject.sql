-- create_progress_invoice: resolve the caller via the Firebase-safe identity
-- helper instead of raw auth.uid(). See
-- 20260615220000_crit3_create_progress_invoice_firebase_subject.sql for rationale.
-- Post crit3 'sub' is the Firebase subject (non-uuid); auth.uid()'s sub::uuid
-- cast raised 22P02 and aborted this user-callable (anon/authenticated) RPC.
-- Resolve the caller's company via private.get_user_company_id() instead.
-- Idempotent + sentinel-guarded. Grants unchanged.

begin;

do $do$
declare
  v_functiondef text;
begin
  v_functiondef := pg_get_functiondef(
    'public.create_progress_invoice(uuid, jsonb)'::regprocedure
  );

  if v_functiondef ~ 'auth\.uid\(\)' then
    v_functiondef := replace(
      v_functiondef,
$old$  SELECT company_id INTO v_caller_company
  FROM users
  WHERE auth_id = auth.uid();$old$,
$new$  -- CRIT-3: resolve the caller's company via the Firebase-safe identity helper
  -- instead of the uid() builtin, which casts the request.jwt subject to uuid
  -- and throws 22P02 for Firebase-bridge (non-uuid) sessions.
  v_caller_company := private.get_user_company_id();$new$
    );

    if v_functiondef ~ 'auth\.uid\(\)' then
      raise exception
        'crit3_progress_invoice_sentinel: failed to remove auth.uid() from create_progress_invoice';
    end if;

    if v_functiondef not like '%v_caller_company := private.get_user_company_id();%' then
      raise exception
        'crit3_progress_invoice_sentinel: helper resolution patch did not apply';
    end if;

    execute v_functiondef;
  end if;
end
$do$;

-- Post-condition: assert the live definition reflects the fix.
do $do$
declare
  v_def text := pg_get_functiondef('public.create_progress_invoice(uuid, jsonb)'::regprocedure);
begin
  if v_def ~ 'auth\.uid\(\)' then
    raise exception 'crit3_progress_invoice_sentinel: create_progress_invoice still calls auth.uid() after migration';
  end if;
  if v_def not like '%v_caller_company := private.get_user_company_id();%' then
    raise exception 'crit3_progress_invoice_sentinel: caller company not resolved via private.get_user_company_id()';
  end if;
end
$do$;

commit;
