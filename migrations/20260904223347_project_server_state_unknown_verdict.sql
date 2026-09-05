-- Bug bf2a75fb hardening. public.project_server_state collapsed two different
-- facts into one answer: when private.get_user_company_id() returns NULL — the
-- caller could not be resolved to a company at all — the subselect yields no
-- row and the function answered 'absent' for a LIVE project.
--
-- Measured in prod before this change:
--   Charlie's JWT -> company a612edc0 -> 'active'
--   no JWT claims -> NULL            -> 'absent'   (FALSE)
--
-- iOS treats 'absent' as proof the project is gone: ImageSyncManager files a
-- PROJECT_ROW_MISSING auto-bug and settle(.heldProjectAbsent) calls
-- removePortalMirrors(urls:), dropping the queued portal mirror PERMANENTLY.
-- Any user whose users row has a NULL company_id would silently lose photo
-- delivery against a perfectly live job.
--
-- Separates "I could not identify you" from "no such row".
--
-- SAFE FOR ALREADY-SHIPPED BUILDS: signature, return type and language are
-- unchanged; only a new possible string value appears. iOS decodes the verdict
-- through a String-backed enum's init(rawValue:), so an unrecognized value is
-- nil and ImageSyncManager maps nil to .retryQueued — old builds degrade to
-- "queue it and try again", which is the desired behaviour. No App Store
-- release is required for this to be safe.

create or replace function public.project_server_state(p_project_id uuid)
returns text
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'private', 'pg_temp'
as $function$
  -- 'unknown' means the CALLER could not be resolved to a company, not that
  -- the row is missing. Callers must treat it as "no answer" and retry, never
  -- as evidence of deletion.
  select case
    when (select private.get_user_company_id()) is null then 'unknown'
    else coalesce(
      (select case when p.deleted_at is null then 'active' else 'deleted' end
         from public.projects p
        where p.id = p_project_id
          and p.company_id = (select private.get_user_company_id())),
      'absent')
  end;
$function$;
