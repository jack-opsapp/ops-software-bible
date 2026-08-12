-- Harden onboarding RPCs for cross-platform signup.
-- IDENTITY MODEL: OPS authenticates via Firebase, bridged into Supabase as the
-- `authenticated` role. The JWT `sub` is a Firebase UID (NOT a UUID), so
-- `auth.uid()` is unusable here. Identity is matched by `auth.jwt() ->> 'email'`
-- / `'sub'`, mirroring `private.get_user_company_id()`. Caller role is read from
-- the JWT claims (NOT current_user, the SECURITY DEFINER owner); only the
-- `service_role` skips caller validation. Company-code proof is enforced only
-- when supplied AND the company has a code, so the shipped 2-arg iOS build and
-- code-less invite companies keep working.

DROP FUNCTION IF EXISTS public.join_user_to_company(UUID, UUID);

CREATE OR REPLACE FUNCTION public.join_user_to_company(
  p_user_id UUID,
  p_company_id UUID,
  p_company_code TEXT DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_user RECORD;
  v_company RECORD;
  v_invitation RECORD;
  v_existing_role_id UUID;
  v_role_id UUID;
  v_role_name TEXT;
  v_seat_granted BOOLEAN := false;
  v_seated_count INT;
  v_user_id_text TEXT;
  v_unassigned_role_id UUID := '00000000-0000-0000-0000-000000000006';
  v_new_member_name TEXT;
  v_new_member_first_name TEXT;
  v_is_service_role BOOLEAN;
  v_jwt_email TEXT;
  v_jwt_sub TEXT;
  v_expected_company_code TEXT;
BEGIN
  v_user_id_text := p_user_id::text;

  v_is_service_role := (
    COALESCE(
      auth.jwt() ->> 'role',
      NULLIF(current_setting('request.jwt.claim.role', true), ''),
      ''
    ) = 'service_role'
  );

  IF NOT v_is_service_role THEN
    v_jwt_email := auth.jwt() ->> 'email';
    v_jwt_sub   := auth.jwt() ->> 'sub';

    -- Firebase identities matched by email or firebase_uid/auth_id (= JWT sub);
    -- never auth.uid() (the Firebase sub is not a UUID and would raise).
    IF NOT EXISTS (
      SELECT 1
        FROM users
       WHERE id = p_user_id
         AND deleted_at IS NULL
         AND (
           (v_jwt_email IS NOT NULL AND lower(email) = lower(v_jwt_email))
           OR (v_jwt_sub IS NOT NULL AND firebase_uid = v_jwt_sub)
           OR (v_jwt_sub IS NOT NULL AND auth_id = v_jwt_sub)
         )
    ) THEN
      RETURN jsonb_build_object(
        'error', 'Caller cannot join this user.',
        'code', 'caller_user_mismatch'
      );
    END IF;
  END IF;

  SELECT id, email, phone, company_id, first_name, last_name
    INTO v_user
    FROM users
   WHERE id = p_user_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'User not found.', 'code', 'user_not_found');
  END IF;

  IF v_user.company_id IS NOT NULL AND v_user.company_id <> p_company_id THEN
    RETURN jsonb_build_object(
      'error', 'User already belongs to another company.',
      'code', 'company_reassignment_denied'
    );
  END IF;

  SELECT id, name, company_code, max_seats, seated_employee_ids, admin_ids
    INTO v_company
    FROM companies
   WHERE id = p_company_id AND deleted_at IS NULL
   FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Company not found.', 'code', 'company_not_found');
  END IF;

  -- Company-code proof: enforced only when a code is supplied AND the company
  -- has one. service_role enforces the code at the API-route layer instead.
  IF NOT v_is_service_role
     AND p_company_code IS NOT NULL
     AND trim(p_company_code) <> '' THEN
    v_expected_company_code := lower(trim(COALESCE(v_company.company_code, '')));

    IF v_expected_company_code <> ''
       AND lower(trim(p_company_code)) <> v_expected_company_code THEN
      RETURN jsonb_build_object(
        'error', 'Company code does not match.',
        'code', 'company_code_mismatch'
      );
    END IF;
  END IF;

  v_seated_count := COALESCE(array_length(v_company.seated_employee_ids, 1), 0);

  IF NOT (v_user_id_text = ANY(COALESCE(v_company.seated_employee_ids, ARRAY[]::text[])))
     AND v_seated_count >= COALESCE(v_company.max_seats, 0) THEN
    RETURN jsonb_build_object(
      'error', 'Company has no open seats.',
      'code', 'seat_full',
      'seat_granted', false
    );
  END IF;

  UPDATE users
     SET company_id = p_company_id,
         updated_at = NOW()
   WHERE id = p_user_id;

  v_invitation := NULL;

  IF v_user.email IS NOT NULL THEN
    SELECT id, role_id, invited_by
      INTO v_invitation
      FROM team_invitations
     WHERE company_id = p_company_id
       AND email = v_user.email
       AND status = 'pending'
       AND expires_at > NOW()
     ORDER BY created_at DESC
     LIMIT 1;
  END IF;

  IF v_invitation.id IS NULL AND v_user.phone IS NOT NULL THEN
    SELECT id, role_id, invited_by
      INTO v_invitation
      FROM team_invitations
     WHERE company_id = p_company_id
       AND phone = v_user.phone
       AND status = 'pending'
       AND expires_at > NOW()
     ORDER BY created_at DESC
     LIMIT 1;
  END IF;

  SELECT role_id INTO v_existing_role_id
    FROM user_roles
   WHERE user_id = v_user_id_text;

  IF v_invitation.id IS NOT NULL THEN
    UPDATE team_invitations
       SET status = 'accepted', updated_at = NOW()
     WHERE id = v_invitation.id;

    v_role_id := COALESCE(v_invitation.role_id, v_existing_role_id, v_unassigned_role_id);
  ELSIF v_existing_role_id IS NOT NULL THEN
    v_role_id := v_existing_role_id;
  ELSE
    v_role_id := v_unassigned_role_id;
  END IF;

  INSERT INTO user_roles (user_id, role_id)
  VALUES (v_user_id_text, v_role_id)
  ON CONFLICT (user_id) DO UPDATE SET role_id = EXCLUDED.role_id;

  SELECT lower(name) INTO v_role_name FROM roles WHERE id = v_role_id;

  IF v_role_name NOT IN ('admin', 'owner', 'office', 'operator', 'crew', 'unassigned') THEN
    v_role_name := 'unassigned';
  END IF;

  UPDATE users
     SET role = COALESCE(v_role_name, 'unassigned')
   WHERE id = p_user_id;

  IF NOT (v_user_id_text = ANY(COALESCE(v_company.seated_employee_ids, ARRAY[]::text[]))) THEN
    UPDATE companies
       SET seated_employee_ids = array_append(COALESCE(seated_employee_ids, ARRAY[]::text[]), v_user_id_text),
           updated_at = NOW()
     WHERE id = p_company_id;

    v_seat_granted := true;
  END IF;

  v_new_member_first_name := COALESCE(NULLIF(TRIM(v_user.first_name), ''), 'A new member');
  v_new_member_name := TRIM(CONCAT_WS(' ', v_user.first_name, v_user.last_name));
  IF v_new_member_name = '' THEN
    v_new_member_name := COALESCE(v_user.email, v_new_member_first_name);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'company_id', p_company_id,
    'role_id', v_role_id,
    'role_name', COALESCE(v_role_name, 'unassigned'),
    'seat_granted', v_seat_granted,
    'invitation_found', v_invitation.id IS NOT NULL,
    'admin_ids', COALESCE(v_company.admin_ids, ARRAY[]::text[]),
    'invited_by', v_invitation.invited_by,
    'new_member_id', p_user_id,
    'new_member_name', v_new_member_name,
    'new_member_first_name', v_new_member_first_name,
    'company_name', v_company.name
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.initialize_company_defaults(p_company_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_is_service_role BOOLEAN;
BEGIN
  v_is_service_role := (
    COALESCE(
      auth.jwt() ->> 'role',
      NULLIF(current_setting('request.jwt.claim.role', true), ''),
      ''
    ) = 'service_role'
  );

  IF NOT v_is_service_role
     AND private.get_user_company_id() IS DISTINCT FROM p_company_id THEN
    RAISE EXCEPTION 'Caller cannot initialize this company.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM task_types WHERE company_id = p_company_id AND deleted_at IS NULL) THEN
    INSERT INTO task_types (company_id, display, color, is_default, display_order) VALUES
      (p_company_id, 'Quote',        '#B5A381', true, 0),
      (p_company_id, 'Installation', '#8195B5', true, 1),
      (p_company_id, 'Repair',       '#B58289', true, 2),
      (p_company_id, 'Inspection',   '#9DB582', true, 3),
      (p_company_id, 'Consultation', '#A182B5', true, 4),
      (p_company_id, 'Follow-up',    '#C4A868', true, 5);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM inventory_units WHERE company_id = p_company_id AND deleted_at IS NULL) THEN
    INSERT INTO inventory_units (company_id, display, abbreviation, dimension, is_default, sort_order) VALUES
      (p_company_id, 'ea',         'ea',     'count',  true, 0),
      (p_company_id, 'box',        'box',    'count',  true, 1),
      (p_company_id, 'ft',         'ft',     'length', true, 2),
      (p_company_id, 'm',          'm',      'length', true, 3),
      (p_company_id, 'kg',         'kg',     'weight', true, 4),
      (p_company_id, 'lb',         'lb',     'weight', true, 5),
      (p_company_id, 'gal',        'gal',    'volume', true, 6),
      (p_company_id, 'L',          'L',      'volume', true, 7),
      (p_company_id, 'roll',       'roll',   'count',  true, 8),
      (p_company_id, 'sheet',      'sheet',  'count',  true, 9),
      (p_company_id, 'bag',        'bag',    'count',  true, 10),
      (p_company_id, 'pallet',     'pallet', 'count',  true, 11),
      (p_company_id, 'hour',       'hr',     'time',   true, 12),
      (p_company_id, 'day',        'd',      'time',   true, 13),
      (p_company_id, 'linear ft',  'LF',     'length', true, 14),
      (p_company_id, 'linear m',   'LM',     'length', true, 15),
      (p_company_id, 'sq ft',      'sqft',   'area',   true, 16),
      (p_company_id, 'sq m',       'sqm',    'area',   true, 17),
      (p_company_id, 'cu yd',      'cu yd',  'volume', true, 18),
      (p_company_id, 'cu m',       'cu m',   'volume', true, 19);
  END IF;

  INSERT INTO company_settings (company_id)
  VALUES (p_company_id::TEXT)
  ON CONFLICT (company_id) DO NOTHING;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.join_user_to_company(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.join_user_to_company(UUID, UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.join_user_to_company(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_user_to_company(UUID, UUID, TEXT) TO service_role;

REVOKE EXECUTE ON FUNCTION public.initialize_company_defaults(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.initialize_company_defaults(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.initialize_company_defaults(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.initialize_company_defaults(UUID) TO service_role;
