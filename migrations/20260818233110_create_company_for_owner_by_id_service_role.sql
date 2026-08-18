-- Atomic company bootstrap for the web signup step, callable by service_role.
--
-- `/api/setup/progress` (step "company") ran four autocommit statements:
-- insert companies -> initialize_company_defaults -> upsert Owner user_roles ->
-- update users. A failure in the last two left the company committed and the
-- user unlinked; the retry re-entered the create branch and minted a SECOND
-- company, orphaning the first. Five orphans accumulated for one production
-- account holder in 33 seconds this way.
--
-- `public.create_company_for_owner` cannot be reused here: it resolves its
-- caller via auth.jwt() ->> 'sub' and raises NO_JWT under the service-role
-- client that route uses. This is that function's service-role twin -- the
-- owner is named explicitly instead of derived from the JWT.
--
-- SECURITY: because the caller names the owner, EXECUTE is granted to
-- service_role ONLY. Granting it to `authenticated` would let any signed-in
-- user bootstrap a company onto an arbitrary user id.
create or replace function public.create_company_for_owner_by_id(
  p_user_id uuid,
  p_name text,
  p_industries text[] default null,
  p_company_size text default null,
  p_company_age text default null,
  p_weather_dependent boolean default null,
  p_referral_method text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_user public.users%rowtype;
  v_company_id uuid;
  v_code text;
  v_owner_role_id uuid;
  v_attempts integer := 0;
  v_inserted boolean := false;
  v_constraint text;
  v_already boolean := false;
  v_jwt_role text;
  v_claim_singular text;
  v_claims_plural text;
  v_elevated text;
begin
  -- Belt-and-suspenders behind the GRANT: this function trusts p_user_id, so a
  -- client-role caller must never reach it.
  v_jwt_role := coalesce(
    auth.jwt() ->> 'role',
    nullif(current_setting('request.jwt.claim.role', true), ''),
    ''
  );
  if v_jwt_role in ('authenticated', 'anon') then
    raise exception 'NOT_SERVICE_ROLE' using errcode = '42501';
  end if;

  if p_user_id is null then
    raise exception 'NO_USER_ROW' using errcode = 'P0002';
  end if;
  if p_name is null or btrim(p_name) = '' then
    raise exception 'INVALID_NAME' using errcode = 'P0005';
  end if;

  -- Same advisory-lock key as create_company_for_owner, so a web attempt and a
  -- concurrent iOS attempt for the same owner serialize against each other.
  perform pg_advisory_xact_lock(
    hashtext('create_company_for_owner'),
    hashtext(p_user_id::text)
  );

  select * into v_user
    from public.users
   where id = p_user_id
     and deleted_at is null
   for update;
  if v_user.id is null then
    raise exception 'NO_USER_ROW' using errcode = 'P0002';
  end if;

  -- guard_user_roles_final_state() rejects role writes for an inactive user
  -- ("role assignment", 23514). Fail with a legible token instead.
  if not coalesce(v_user.is_active, false) then
    raise exception 'USER_INACTIVE' using errcode = 'P0007';
  end if;

  if v_user.company_id is not null and exists (
    select 1 from public.companies
     where id = v_user.company_id and deleted_at is null
  ) then
    raise exception 'ALREADY_IN_COMPANY' using errcode = 'P0003';
  end if;

  -- Adopt an unlinked company this user already holds rather than minting a
  -- second one. THIS is what makes a retry after a mid-step failure idempotent:
  -- the orphan left by the failed attempt is claimed and completed, not
  -- duplicated. Oldest-first matches create_company_for_owner's choice.
  select id, company_code
    into v_company_id, v_code
    from public.companies
   where account_holder_id = p_user_id::text
     and deleted_at is null
   order by created_at, id
   limit 1
   for update;

  if v_company_id is not null then
    v_already := true;
    update public.companies
       set name              = btrim(p_name),
           industries        = coalesce(p_industries, industries, '{}'::text[]),
           company_size      = coalesce(p_company_size, company_size),
           company_age       = coalesce(p_company_age, company_age),
           weather_dependent = coalesce(p_weather_dependent, weather_dependent),
           referral_method   = coalesce(p_referral_method, referral_method),
           admin_ids         = case
                                 when p_user_id::text = any(coalesce(admin_ids, array[]::text[]))
                                   then admin_ids
                                 else coalesce(admin_ids, array[]::text[]) || p_user_id::text
                               end,
           updated_at        = now()
     where id = v_company_id;
  end if;

  -- Mint the crew join code. Entropy comes from pgcrypto's CSPRNG, not
  -- random(): the code is a bearer credential (anyone holding it can join the
  -- company), which is why the web path it replaces used the Web Crypto
  -- CSPRNG. 256 is an exact multiple of 32, so byte -> symbol carries no
  -- modulo bias. Alphabet/length/retry bound match create_company_for_owner.
  if v_company_id is null or v_code is null then
    loop
      v_attempts := v_attempts + 1;
      if v_attempts > 20 then
        raise exception 'CODE_GENERATION_EXHAUSTED' using errcode = 'P0006';
      end if;

      v_code := (
        select string_agg(
                 substr(
                   'ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                   (get_byte(b.v_bytes, g) % 32) + 1,
                   1
                 ),
                 ''
               )
          from (select extensions.gen_random_bytes(8) as v_bytes) b,
               generate_series(0, 7) g
      );
      continue when exists (
        select 1 from public.companies where upper(company_code) = v_code
      );

      begin
        if v_company_id is null then
          insert into public.companies (
            name, industries, company_size, company_age, weather_dependent,
            referral_method, company_code, admin_ids, account_holder_id,
            created_at, updated_at
          )
          values (
            btrim(p_name),
            coalesce(p_industries, '{}'::text[]),
            p_company_size,
            p_company_age,
            p_weather_dependent,
            p_referral_method,
            v_code,
            array[p_user_id::text],
            p_user_id::text,
            now(),
            now()
          )
          returning id into v_company_id;
        else
          update public.companies
             set company_code = v_code,
                 updated_at = now()
           where id = v_company_id;
        end if;
        v_inserted := true;
      exception when unique_violation then
        get stacked diagnostics v_constraint = constraint_name;
        if v_constraint is distinct from 'idx_companies_company_code' then
          raise;
        end if;
        v_inserted := false;
      end;
      exit when v_inserted;
    end loop;
  end if;

  select id into v_owner_role_id
    from public.roles
   where name = 'Owner' and is_preset and company_id is null
   limit 1;
  if v_owner_role_id is null then
    raise exception 'OWNER_ROLE_MISSING' using errcode = 'P0004';
  end if;

  -- Owner role seeding -- write order is load-bearing (bible 04 §
  -- "Owner role seeding"). The deferrable constraint trigger
  -- trg_user_roles_final_state -> private.guard_user_roles_final_state()
  -- raises target_is_admin (42501) when the target already reads as a company
  -- admin. It tests admin-ness through
  -- private.permission_user_is_admin(u.id, u.company_id), which compares
  -- u.company_id = p_company_id -- NULL while the user is detached, so the
  -- user reads as a non-admin and the write is legal. Detach, force the
  -- deferred trigger to fire IMMEDIATE while detached, then restore the final
  -- owner state. Deferred (the default) would evaluate at COMMIT, after the
  -- restore, and raise.
  update public.users
     set company_id = null,
         is_company_admin = false,
         updated_at = now()
   where id = p_user_id
     and (company_id is not null or coalesce(is_company_admin, false));

  set constraints trg_user_roles_final_state immediate;
  insert into public.user_roles (user_id, role_id)
  values (p_user_id::text, v_owner_role_id)
  on conflict (user_id) do update
    set role_id = excluded.role_id;
  set constraints trg_user_roles_final_state deferred;

  update public.users
     set company_id = v_company_id,
         role = 'owner',
         is_company_admin = true,
         user_type = 'company',
         updated_at = now()
   where id = p_user_id;

  -- initialize_company_defaults authorizes service_role OR a caller whose own
  -- company matches. Elevate for the nested call so this works no matter which
  -- trusted channel invoked us, then restore the claims exactly as
  -- create_company_for_owner does.
  v_claim_singular := current_setting('request.jwt.claim', true);
  v_claims_plural  := current_setting('request.jwt.claims', true);
  v_elevated := (
    coalesce(auth.jwt(), '{}'::jsonb) || jsonb_build_object('role', 'service_role')
  )::text;
  perform set_config('request.jwt.claim', v_elevated, true);
  perform set_config('request.jwt.claims', v_elevated, true);

  perform public.initialize_company_defaults(v_company_id);

  perform set_config('request.jwt.claim', coalesce(v_claim_singular, ''), true);
  perform set_config('request.jwt.claims', coalesce(v_claims_plural, ''), true);

  return jsonb_build_object(
    'company_id', v_company_id,
    'company_code', v_code,
    'already_existed', v_already
  );
end;
$function$;

revoke all on function public.create_company_for_owner_by_id(
  uuid, text, text[], text, text, boolean, text
) from public, anon, authenticated;

grant execute on function public.create_company_for_owner_by_id(
  uuid, text, text[], text, text, boolean, text
) to service_role;

comment on function public.create_company_for_owner_by_id(
  uuid, text, text[], text, text, boolean, text
) is
  'Service-role twin of create_company_for_owner: bootstraps a company for an '
  'explicitly named owner in ONE transaction (company + join code + Owner '
  'user_roles row + owner labels + initialize_company_defaults). Adopts an '
  'existing unlinked company for the same account_holder_id so a retry after a '
  'partial failure completes it instead of orphaning it. NOT granted to '
  'authenticated -- the caller names the owner.';
