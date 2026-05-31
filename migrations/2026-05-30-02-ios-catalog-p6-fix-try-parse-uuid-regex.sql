-- 2026-05-30-02-ios-catalog-p6-fix-try-parse-uuid-regex.sql
--
-- BLOCKER FIX (P6 estimate-to-job). The LIVE definition of private.try_parse_uuid
-- drifted from its source migration (2026-05-27-04 line 35): the live regex was
--   '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'   (four groups, 8-4-4-12)
-- which is MISSING the third {4} group, so it returned NULL for EVERY valid uuid.
--
-- Consequence: public.accept_estimate_to_job does
--     v_project_id := private.try_parse_uuid(v_project_result ->> 'project_id');
--     if v_project_id is null then raise 'accepted_project_id_missing' errcode 23514;
-- so EVERY estimate acceptance aborted and rolled back (clean uuid or legacy id alike).
-- It also collapsed the material-demand resolver (resolve_catalog_variant_for_material_demand
-- and persist_estimate_material_booking_projection consume try_parse_uuid throughout).
--
-- This restores the canonical five-group (8-4-4-4-12) pattern from source. Additive: no
-- schema change; CREATE OR REPLACE preserves existing ownership and EXECUTE grants
-- (anon, authenticated, postgres). Idempotent / re-runnable.

create or replace function private.try_parse_uuid(p_value text)
  returns uuid
  language plpgsql
  immutable
  set search_path to 'public', 'private', 'pg_temp'
as $function$
begin
  if p_value is null then
    return null;
  end if;

  if btrim(p_value) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return btrim(p_value)::uuid;
  end if;

  return null;
end;
$function$;

-- Regression guard: fail loudly if the parser ever rejects a valid uuid or accepts junk.
do $$
begin
  if private.try_parse_uuid('00000000-0000-4000-8000-000000000000') is null then
    raise exception 'try_parse_uuid regression: rejected a valid uuid';
  end if;
  if private.try_parse_uuid('not-a-uuid') is not null then
    raise exception 'try_parse_uuid regression: accepted a non-uuid';
  end if;
end;
$$;
