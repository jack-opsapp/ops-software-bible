-- SYSTEMS REPAIR W1-6 — applied to prod ijeekuhbatykdomumfjx as
-- `company_purge_definer_for_owner_only_tables` (2026-07-30).
--
-- WHY: a live rehearsal of POST /api/data/delete-account against a disposable tenant stopped
-- at acting-step 23 of 198 — "count rows to purge in email_outbound_edit_promotions" — because
-- 15 tables in the deletion plan are granted to `postgres` ONLY. service_role holds no
-- privileges on them, so the route could not even count the rows. EVERY real account deletion
-- would have failed at the first one. Neither the FK-ordering proof nor the 91-test suite could
-- see this: privileges only exist at runtime against the real database.
--
-- The 15 are trigger-fed ledgers, delivery records and the outbound-email learning corpus —
-- the last of which holds customers' own email content. They are deliberately unreachable
-- from PostgREST.
--
-- DECISION (Jackson, 2026-07-30): keep the lockdown; open one narrow, auditable door. The
-- rejected alternative was granting service_role standing SELECT+DELETE on all 15, which would
-- permanently widen access for every backend code path to solve a once-per-account problem.
--
-- The route calls this in place, at the step the existing plan already schedules, so the
-- FK-depth ordering verified against all 590 live foreign-key constraints remains valid.
-- It is also one round trip instead of two, which removes the count/delete race.
--
-- Verified in prod after apply: service_role may EXECUTE; anon and authenticated may not;
-- SECURITY DEFINER owned by postgres; allowlisted calls succeed against both the uuid and the
-- text company_id variants; and `projects`, `companies`, an injection-shaped table name, and a
-- NULL company are all rejected (4/4 guard assertions, with public.clients intact afterwards).

CREATE OR REPLACE FUNCTION public.purge_company_rows(p_table text, p_company_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  -- Exactly the tables service_role cannot reach. Nothing else is purgeable here.
  v_allowed constant text[] := ARRAY[
    'email_assignment_contact_form_draft_queue',
    'email_import_provider_operations',
    'email_outbound_edit_evidence',
    'email_outbound_edit_promotions',
    'email_outbound_learning_queue',
    'email_outbound_memory_evidence',
    'email_outbound_writing_samples',
    'email_provider_mutation_attempts',
    'opportunity_conversion_notification_deliveries',
    'phase_c_category_auto_send_acceptances',
    'project_status_lifecycle_outbox',
    'task_mutation_events',
    'task_schedule_automation_outbox',
    'unassigned_lead_assignment_deliveries',
    'user_permission_change_deliveries'
  ];
  v_col_type text;
  v_deleted  bigint;
BEGIN
  IF p_company_id IS NULL THEN
    RAISE EXCEPTION 'purge_company_rows: p_company_id is required'
      USING ERRCODE = '22004';
  END IF;

  IF NOT (p_table = ANY (v_allowed)) THEN
    RAISE EXCEPTION 'purge_company_rows: % is not purgeable through this function', p_table
      USING ERRCODE = '42501';
  END IF;

  SELECT c.data_type INTO v_col_type
    FROM information_schema.columns c
   WHERE c.table_schema = 'public'
     AND c.table_name  = p_table
     AND c.column_name = 'company_id';

  IF v_col_type IS NULL THEN
    RAISE EXCEPTION 'purge_company_rows: %.company_id not found', p_table
      USING ERRCODE = '42703';
  END IF;

  -- Cast the PARAMETER to the column's type; never cast the column (that would
  -- defeat the company_id index on these tables). 12 are uuid, 3 are text.
  EXECUTE format(
    'DELETE FROM public.%I WHERE company_id = $1::%s',
    p_table,
    CASE WHEN v_col_type = 'uuid' THEN 'uuid' ELSE 'text' END
  ) USING p_company_id;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- SECURITY DEFINER functions in `public` are EXECUTE-able by PUBLIC (hence anon and
-- authenticated) by default. Close that and grant only the backend identity.
REVOKE ALL ON FUNCTION public.purge_company_rows(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.purge_company_rows(text, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_company_rows(text, uuid) TO service_role;
