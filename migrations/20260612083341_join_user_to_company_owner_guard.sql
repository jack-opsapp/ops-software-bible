CREATE OR REPLACE FUNCTION public.join_user_to_company(p_user_id uuid, p_company_id uuid, p_company_code text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- Onboarding rebuild spec 6.2: rail-notification fan-out state.
  v_admin_id TEXT;
  v_notif_role TEXT;
  v_notif_has_role BOOLEAN;
  v_notif_title TEXT;
  v_notif_body TEXT;
  v_notif_persistent BOOLEAN;
  v_notif_action_label TEXT;
  v_notif_action_url TEXT;
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

  SELECT id, name, company_code, max_seats, seated_employee_ids, admin_ids, account_holder_id
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

  -- Onboarding rebuild spec 6.2: the employee join record (user_type +
  -- is_company_admin) is written here, atomically with the join. This replaces
  -- the iOS client's fire-and-forget post-RPC PostgREST update; the RPC is the
  -- only writer of these fields on the join path.
  -- Owner guard (spec 6.1): when the joining user is the company's owner
  -- (account_holder_id) or one of its admins, skip the user_type /
  -- is_company_admin overwrite — the owner record is pinned at
  -- user_type='company', is_company_admin=true and must never be demoted by a
  -- re-join through this RPC. company_id and updated_at are always written.
  UPDATE users
     SET company_id = p_company_id,
         user_type = CASE
           WHEN v_user_id_text = v_company.account_holder_id
                OR v_user_id_text = ANY(COALESCE(v_company.admin_ids, ARRAY[]::text[]))
           THEN user_type
           ELSE 'employee'
         END,
         is_company_admin = CASE
           WHEN v_user_id_text = v_company.account_holder_id
                OR v_user_id_text = ANY(COALESCE(v_company.admin_ids, ARRAY[]::text[]))
           THEN is_company_admin
           ELSE false
         END,
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

  -- Onboarding rebuild spec 6.2: per-admin "team member joined" rail
  -- notifications, fanned out here so iOS joins produce the same rail rows as
  -- web joins. Mirrors ops-web /api/auth/join-company + buildMemberJoinedCopy
  -- byte-for-byte: same type ('role_needed'), titles/bodies, persistence,
  -- action url/label, and the same dedupe surface (create_notification_if_new
  -- inserts with dedupe_key NULL; the partial unique indexes on
  -- (user_id, company_id, type, title-while-unread) plus ON CONFLICT DO
  -- NOTHING dedupe). Until the web route's own fan-out is removed (Task 1.3)
  -- both writers fire; identical payloads make the second insert a no-op.
  -- Push delivery (OneSignal) intentionally stays client/route-side.
  -- Best-effort by contract: a notification failure must never abort a join.
  BEGIN
    v_notif_role := COALESCE(v_role_name, 'unassigned');
    v_notif_has_role := v_notif_role <> 'unassigned';
    v_notif_action_url := '/settings?tab=team&assignRole=' || p_user_id::text;

    IF v_notif_has_role AND v_seat_granted THEN
      v_notif_title := v_new_member_first_name || ' joined your crew';
      v_notif_body := v_new_member_first_name || ' is on as ' || v_notif_role || '. Seated and ready.';
      v_notif_persistent := false;
      v_notif_action_label := 'VIEW MEMBER';
    ELSIF v_notif_has_role AND NOT v_seat_granted THEN
      v_notif_title := v_new_member_first_name || ' joined your crew';
      v_notif_body := v_new_member_first_name || ' is on as ' || v_notif_role || '. Unseated — shift seats or upgrade to give them access.';
      v_notif_persistent := true;
      v_notif_action_label := 'VIEW MEMBER';
    ELSIF NOT v_notif_has_role AND v_seat_granted THEN
      v_notif_title := v_new_member_first_name || ' needs a role';
      v_notif_body := v_new_member_first_name || ' joined your crew. Tap to assign a role.';
      v_notif_persistent := true;
      v_notif_action_label := 'ASSIGN ROLE';
    ELSE
      v_notif_title := v_new_member_first_name || ' needs a role';
      v_notif_body := v_new_member_first_name || ' joined your crew. Unseated — assign a role and free up a seat.';
      v_notif_persistent := true;
      v_notif_action_label := 'ASSIGN ROLE';
    END IF;

    FOREACH v_admin_id IN ARRAY COALESCE(v_company.admin_ids, ARRAY[]::text[]) LOOP
      BEGIN
        PERFORM create_notification_if_new(
          p_user_id      => v_admin_id,
          p_company_id   => p_company_id::text,
          p_type         => 'role_needed',
          p_title        => v_notif_title,
          p_body         => v_notif_body,
          p_persistent   => v_notif_persistent,
          p_action_url   => v_notif_action_url,
          p_action_label => v_notif_action_label,
          p_project_id   => NULL
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'join_user_to_company: rail notification failed for admin % (company %): %', v_admin_id, p_company_id, SQLERRM;
      END;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'join_user_to_company: notification fan-out failed (company %): %', p_company_id, SQLERRM;
  END;

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
$function$
