-- Self-heal for the email/password firebase_uid linking gap. Links an unlinked
-- users row by the Firebase-signed VERIFIED email (the unresolvable-sub row can't
-- link itself via RLS). Only fills NULL identities (never re-keys a linked
-- account), requires email_verified, excludes soft-deleted rows. Never auth.uid().
create or replace function public.heal_user_identity()
returns uuid
language plpgsql
volatile
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_sub      text := nullif(auth.jwt() ->> 'sub', '');
  v_email    text := lower(nullif(auth.jwt() ->> 'email', ''));
  v_verified boolean := coalesce((auth.jwt() ->> 'email_verified')::boolean, false);
  v_id uuid;
begin
  if v_sub is null or v_email is null then
    return null;
  end if;

  select id into v_id
    from public.users
   where (auth_id = v_sub or firebase_uid = v_sub)
     and deleted_at is null
   limit 1;
  if found then
    return v_id;
  end if;

  if not v_verified then
    return null;
  end if;

  update public.users u
     set auth_id = v_sub,
         firebase_uid = v_sub,
         updated_at = now()
   where u.id = (
     select id
       from public.users
      where lower(email) = v_email
        and auth_id is null
        and firebase_uid is null
        and deleted_at is null
      order by created_at desc
      limit 1
   )
   returning u.id into v_id;

  return v_id;
end;
$$;

grant execute on function public.heal_user_identity() to anon, authenticated, service_role;
