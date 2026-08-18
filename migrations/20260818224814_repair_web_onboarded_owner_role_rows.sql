do $repair$
declare
  v_owner_role_id constant uuid := '00000000-0000-0000-0000-000000000002';
  v_ids constant uuid[] := array[
    'ddb5093e-2258-4c29-b743-a3c84ee7f223',  -- Dre.L1@hotmail.com / Brittlewood
    'd6408c02-6de9-477f-afd7-816bcd50d1bf',  -- service@fabersappliancerepair.com
    'a5466247-ae7e-46cf-a697-39923399f5a0',  -- admin@marnethousing.com
    '288501bc-0126-438c-8715-f805aeceefa7',  -- dereknoreski@gmail.com
    '1a2b388e-fc9c-47d9-80bc-b696dc95f3c0'   -- jacksonsweet.1.0@gmail.com
  ];
  v_id uuid;
  v_company_id uuid;
  v_code text;
  v_attempts integer;
  v_done boolean;
  v_constraint text;
  v_n integer;
begin
  -- Guard 0: the Owner preset must be exactly what create_company_for_owner resolves.
  if not exists (
    select 1 from public.roles
     where id = v_owner_role_id and name = 'Owner' and is_preset and company_id is null
  ) then
    raise exception 'OWNER_ROLE_MISSING';
  end if;

  -- Guard 1: re-assert the full broken signature for all five, inside the transaction.
  -- If anything drifted since the snapshot, abort rather than mutate the wrong account.
  select count(*) into v_n
    from public.users u
    join public.companies c on c.id = u.company_id
   where u.id = any(v_ids)
     and u.deleted_at is null
     and c.deleted_at is null
     and coalesce(u.is_active, false)
     and coalesce(u.is_company_admin, false)
     and u.role = 'unassigned'
     and u.user_type is null
     and c.account_holder_id = u.id::text
     and not exists (select 1 from public.user_roles ur where ur.user_id = u.id::text);
  if v_n <> 5 then
    raise exception 'PRECONDITION_FAILED: expected 5 broken account holders, found %', v_n;
  end if;

  for v_id, v_company_id, v_code in
    select u.id, u.company_id, c.company_code
      from public.users u
      join public.companies c on c.id = u.company_id
     where u.id = any(v_ids)
     order by u.id
  loop
    -- Serialize against concurrent onboarding for this owner, exactly as the RPC does.
    perform pg_advisory_xact_lock(hashtext('create_company_for_owner'), hashtext(v_id::text));
    perform 1 from public.users     where id = v_id         for update;
    perform 1 from public.companies where id = v_company_id for update;

    -- 1. Transiently detach. permission_user_is_admin() compares u.company_id = p_company_id
    --    and is called as (u.id, u.company_id), so a NULL company_id makes that NULL = NULL
    --    -> NULL -> false. This is the only field that defeats the admin test while still
    --    satisfying the guard's role-assignment check.
    update public.users
       set company_id = null, is_company_admin = false
     where id = v_id;

    -- 2. Seed the Owner row with the constraint trigger forced to evaluate NOW, while the
    --    user is not an admin. Deferred (the default) would evaluate at COMMIT, after the
    --    restore below, and raise target_is_admin.
    set constraints trg_user_roles_final_state immediate;
    insert into public.user_roles (user_id, role_id)
    values (v_id::text, v_owner_role_id)
    on conflict (user_id) do update set role_id = excluded.role_id;
    set constraints trg_user_roles_final_state deferred;

    -- 3. Restore the correct final owner state (company_id + admin unchanged from before).
    update public.users
       set company_id = v_company_id,
           role = 'owner',
           is_company_admin = true,
           user_type = 'company',
           updated_at = now()
     where id = v_id;

    -- 4. Mint the crew join code if missing -- byte-for-byte the algorithm in
    --    create_company_for_owner (same alphabet, same 20-attempt bound, same collision path).
    if v_code is null then
      v_attempts := 0;
      v_done := false;
      loop
        v_attempts := v_attempts + 1;
        if v_attempts > 20 then
          raise exception 'CODE_GENERATION_EXHAUSTED';
        end if;
        v_code := (
          select string_agg(
            substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', (floor(random() * 32))::integer + 1, 1), ''
          )
          from generate_series(1, 8)
        );
        continue when exists (
          select 1 from public.companies where upper(company_code) = v_code
        );
        begin
          update public.companies
             set company_code = v_code, updated_at = now()
           where id = v_company_id;
          v_done := true;
        exception when unique_violation then
          get stacked diagnostics v_constraint = constraint_name;
          if v_constraint is distinct from 'idx_companies_company_code' then
            raise;
          end if;
          v_done := false;
        end;
        exit when v_done;
      end loop;
    end if;
  end loop;
end
$repair$;
