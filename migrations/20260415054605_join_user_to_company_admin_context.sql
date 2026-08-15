CREATE OR REPLACE FUNCTION public.join_user_to_company(
  p_user_id UUID,
  p_company_id UUID
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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
BEGIN
  v_user_id_text := p_user_id::text;

  SELECT id, email, phone, company_id, first_name, last_name
    INTO v_user
    FROM users
   WHERE id = p_user_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'User not found');
  END IF;

  SELECT id, name, max_seats, seated_employee_ids, admin_ids
    INTO v_company
    FROM companies
   WHERE id = p_company_id AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Company not found');
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

  v_seated_count := COALESCE(array_length(v_company.seated_employee_ids, 1), 0);

  IF v_seated_count < v_company.max_seats THEN
    IF NOT (v_user_id_text = ANY(COALESCE(v_company.seated_employee_ids, ARRAY[]::text[]))) THEN
      UPDATE companies
         SET seated_employee_ids = array_append(COALESCE(seated_employee_ids, ARRAY[]::text[]), v_user_id_text),
             updated_at = NOW()
       WHERE id = p_company_id;

      v_seat_granted := true;
    END IF;
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
