-- W3 security posture sweep — close `public_bucket_allows_listing` (advisor lint
-- 0025) on the six public buckets. Public object URLs are unaffected (docs-
-- confirmed); the app makes no storage .list() calls. Private buckets untouched.

begin;

drop policy if exists "Anyone can view client images"      on storage.objects; -- client-images
drop policy if exists "Public read images"                 on storage.objects; -- images
drop policy if exists "Anyone can view logos"              on storage.objects; -- logos
drop policy if exists "Anyone can view product thumbnails" on storage.objects; -- product-thumbnails
drop policy if exists "Anyone can view profiles"           on storage.objects; -- profiles
drop policy if exists "project photos select public"       on storage.objects; -- project-photos

do $do$
declare
  v_bad int;
begin
  select count(*) into v_bad
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and policyname in (
      'Anyone can view client images','Public read images','Anyone can view logos',
      'Anyone can view product thumbnails','Anyone can view profiles','project photos select public'
    );
  if v_bad <> 0 then
    raise exception 'sec_w3_bucket_listing_sentinel: % broad listing policy(ies) still present', v_bad;
  end if;
end
$do$;

commit;
