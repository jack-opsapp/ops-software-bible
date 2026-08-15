-- Code-review follow-up (Fix-then-approve) for the onboarding company-creation RPC.
--   Important-1: TOCTOU on the ALREADY_IN_COMPANY guard — re-read users.company_id
--                under FOR UPDATE after the advisory lock; row stays locked to commit.
--   Important-2: idempotent path could return NULL company_code for legacy companies
--                (6 live rows) — mint + persist a real code in that branch.
--   Minor-3: deterministic idempotency lookup (ORDER BY created_at, id).
--   Minor-4: unique_violation handlers re-raise unless the violated constraint is
--            idx_companies_company_code (don't mask unrelated future constraints).
--   Minor-5: typed-error table documented on the function COMMENT.
--   Minor-6: clarifying comment on GUC abort/restore semantics in the elevation block.

CREATE OR REPLACE FUNCTION public.create_company_for_owner(p_name text, p_industries text[] DEFAULT NULL::text[], p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_firebase_uid   text;
  v_user           users%ROWTYPE;
  v_company_id     uuid;
  v_code           text;
  v_owner_role_id  uuid;
  v_attempts       int := 0;
  v_inserted       boolean := false;
  v_constraint     text;
  v_claim_singular text;
  v_claims_plural  text;
  v_elevated       text;
BEGIN
  -- 1. Caller identity from the JWT ONLY (spec §6.1): sub = Firebase UID.
  --    No caller-supplied user id is accepted.
  v_firebase_uid := nullif(auth.jwt() ->> 'sub', '');
  IF v_firebase_uid IS NULL THEN
    RAISE EXCEPTION 'NO_JWT' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_user
    FROM users
   WHERE firebase_uid = v_firebase_uid
     AND deleted_at IS NULL
   LIMIT 1;
  IF v_user.id IS NULL THEN
    -- sync-user race: client retries after POST /api/auth/sync-user completes.
    RAISE EXCEPTION 'NO_USER_ROW' USING ERRCODE = 'P0002';
  END IF;

  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RAISE EXCEPTION 'INVALID_NAME' USING ERRCODE = 'P0005';
  END IF;

  -- 2. Serialize per caller (double-tap / parallel-client safety). Transaction-scoped.
  PERFORM pg_advisory_xact_lock(hashtext('create_company_for_owner'), hashtext(v_user.id::text));

  -- 2b. TOCTOU guard: the users read above happened BEFORE the advisory lock, so a
  --     concurrent join-company commit landing in between would be silently
  --     overwritten by step 6. Re-read company_id under FOR UPDATE so the
  --     ALREADY_IN_COMPANY guard below judges committed state and the users row
  --     stays locked until this transaction commits.
  SELECT company_id INTO v_user.company_id
    FROM users
   WHERE id = v_user.id
   FOR UPDATE;

  -- 3. Idempotency: caller already owns a company -> return it with its REAL stored code.
  SELECT id, company_code INTO v_company_id, v_code
    FROM companies
   WHERE account_holder_id = v_user.id::text
     AND deleted_at IS NULL
   ORDER BY created_at, id
   LIMIT 1;
  IF v_company_id IS NOT NULL THEN
    -- Legacy backfill: pre-RPC companies can carry a NULL company_code. The contract
    -- is "the real stored code", so mint one and persist it before returning.
    IF v_code IS NULL THEN
      LOOP
        v_attempts := v_attempts + 1;
        IF v_attempts > 20 THEN
          RAISE EXCEPTION 'CODE_GENERATION_EXHAUSTED' USING ERRCODE = 'P0006';
        END IF;

        v_code := (
          SELECT string_agg(
                   substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random() * 32))::int + 1, 1),
                   '')
            FROM generate_series(1, 8)
        );

        CONTINUE WHEN EXISTS (SELECT 1 FROM companies WHERE upper(company_code) = v_code);

        BEGIN
          UPDATE companies
             SET company_code = v_code,
                 updated_at   = now()
           WHERE id = v_company_id;
          v_inserted := true;
        EXCEPTION WHEN unique_violation THEN
          GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
          IF v_constraint IS DISTINCT FROM 'idx_companies_company_code' THEN
            RAISE; -- unrelated unique constraint: not a code collision, surface it
          END IF;
          v_inserted := false; -- company_code race; regenerate and retry
        END;

        EXIT WHEN v_inserted;
      END LOOP;
    END IF;

    RETURN jsonb_build_object(
      'company_id', v_company_id,
      'company_code', v_code,
      'already_existed', true
    );
  END IF;

  -- 4. Integrity guard: a member of a live company must not silently detach
  --    (would leak a seat in the old company's seated_employee_ids).
  IF v_user.company_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM companies
        WHERE id = v_user.company_id AND deleted_at IS NULL
     ) THEN
    RAISE EXCEPTION 'ALREADY_IN_COMPANY' USING ERRCODE = 'P0003';
  END IF;

  -- 5. Server-side unique code (spec-pinned scheme: 8 chars, I/O/0/1 excluded) + insert.
  --    The unique partial index idx_companies_company_code backstops the pre-check;
  --    a lost race surfaces as unique_violation and we regenerate.
  LOOP
    v_attempts := v_attempts + 1;
    IF v_attempts > 20 THEN
      RAISE EXCEPTION 'CODE_GENERATION_EXHAUSTED' USING ERRCODE = 'P0006';
    END IF;

    v_code := (
      SELECT string_agg(
               substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random() * 32))::int + 1, 1),
               '')
        FROM generate_series(1, 8)
    );

    CONTINUE WHEN EXISTS (SELECT 1 FROM companies WHERE upper(company_code) = v_code);

    BEGIN
      INSERT INTO companies (
        name, email, phone, address, industries, company_code,
        admin_ids, seated_employee_ids, account_holder_id,
        subscription_status, subscription_plan, trial_start_date, trial_end_date, max_seats,
        created_at, updated_at
      )
      VALUES (
        btrim(p_name), p_email, p_phone, p_address,
        COALESCE(p_industries, '{}'::text[]), v_code,
        ARRAY[v_user.id::text], ARRAY[v_user.id::text], v_user.id::text,
        'trial', 'trial', now(), now() + interval '30 days', 10,
        now(), now()
      )
      RETURNING id INTO v_company_id;
      v_inserted := true;
    EXCEPTION WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
      IF v_constraint IS DISTINCT FROM 'idx_companies_company_code' THEN
        RAISE; -- unrelated unique constraint: not a code collision, surface it
      END IF;
      v_inserted := false; -- company_code race; regenerate and retry
    END;

    EXIT WHEN v_inserted;
  END LOOP;

  -- 6. Owner record on users (spec §6.1 pinned values).
  UPDATE users
     SET company_id       = v_company_id,
         role             = 'owner',
         is_company_admin = true,
         user_type        = 'company',
         updated_at       = now()
   WHERE id = v_user.id;

  -- 7. user_roles -> preset Owner role. user_roles.user_id is TEXT.
  --    Missing preset would recreate the iOS/Web owner-record divergence this RPC
  --    exists to kill, so it fails loudly instead of silently skipping.
  SELECT id INTO v_owner_role_id
    FROM roles
   WHERE name = 'Owner' AND is_preset AND company_id IS NULL
   LIMIT 1;
  IF v_owner_role_id IS NULL THEN
    RAISE EXCEPTION 'OWNER_ROLE_MISSING' USING ERRCODE = 'P0004';
  END IF;

  INSERT INTO user_roles (user_id, role_id)
  VALUES (v_user.id::text, v_owner_role_id)
  ON CONFLICT (user_id) DO UPDATE SET role_id = EXCLUDED.role_id;

  -- 8. Company defaults. initialize_company_defaults guards on
  --    private.get_user_company_id(), which resolves by EXACT jwt-email match —
  --    fragile for case-mismatched or email-less identities. We have already
  --    authenticated the caller via the sub claim and created this company FOR
  --    them, so elevate the role claim transaction-locally for this single call,
  --    then restore the original claims immediately.
  -- On RAISE, transaction/subtransaction abort reverts these transaction-local GUCs — explicit restore is only needed on the success path.
  v_claim_singular := current_setting('request.jwt.claim', true);
  v_claims_plural  := current_setting('request.jwt.claims', true);
  v_elevated := (COALESCE(auth.jwt(), '{}'::jsonb)
                 || jsonb_build_object('role', 'service_role'))::text;
  PERFORM set_config('request.jwt.claim',  v_elevated, true);
  PERFORM set_config('request.jwt.claims', v_elevated, true);

  PERFORM initialize_company_defaults(v_company_id);

  PERFORM set_config('request.jwt.claim',  COALESCE(v_claim_singular, ''), true);
  PERFORM set_config('request.jwt.claims', COALESCE(v_claims_plural, ''), true);

  RETURN jsonb_build_object(
    'company_id', v_company_id,
    'company_code', v_code,
    'already_existed', false
  );
END $function$;

COMMENT ON FUNCTION public.create_company_for_owner(text, text[], text, text, text) IS
'Single shared company-creation path for iOS + OPS-Web onboarding (spec 2026-06-11 §6.1). Identity from JWT sub (Firebase UID) only. Returns {company_id, company_code, already_existed}.

Typed errors — clients MUST match on the message token, not SQLSTATE alone: P0001 is plpgsql''s default RAISE errcode, so NO_JWT shares its SQLSTATE with any bare RAISE EXCEPTION.
  NO_JWT                    P0001  no sub claim in the JWT
  NO_USER_ROW               P0002  no live users row for the Firebase UID (sync-user race; client retries after sync-user completes)
  ALREADY_IN_COMPANY        P0003  caller already belongs to another live company
  OWNER_ROLE_MISSING        P0004  preset Owner role missing from roles
  INVALID_NAME              P0005  p_name is null or blank
  CODE_GENERATION_EXHAUSTED P0006  could not find a unique company code in 20 attempts';
