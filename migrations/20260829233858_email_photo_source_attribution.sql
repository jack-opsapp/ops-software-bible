-- Email photo source attribution: flips the email->project conversion
-- pipeline from source='other' to source='email' and records the email
-- provenance (attachment id + sender address) on each imported photo.
--
-- Prerequisites (both already applied to prod 2026-08-18):
--   20260817220000_photo_source_email_enum.sql       (enum value 'email')
--   20260817220100_project_photo_email_provenance.sql (provenance columns)
--
-- Applied at the ops-web main push GO (origin/main 014c888a, 2026-08-29),
-- per the staged-migration protocol: the deployed web gallery silently
-- drops photos whose source is outside its known set, so the flip and the
-- push ship in the same action.
--
-- The function below is the prod definition of
-- public.complete_email_conversion_photo_job (base verified live before
-- apply: def md5 0eef64538aa105f89762e1c183f83c0f, unchanged since the
-- 2026-08-17 staging), byte-identical except for the source/provenance
-- writes in its two write paths. The sender address is read from the
-- `attachment` row the function has already loaded and validated, so no
-- extra query is introduced.

CREATE OR REPLACE FUNCTION public.complete_email_conversion_photo_job(p_job_id uuid, p_generation bigint, p_lease_token uuid, p_project_storage_path text, p_project_photo_url text, p_project_content_sha256 text, p_project_verified_size_bytes bigint, p_filename text DEFAULT NULL::text, p_occurred_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'pg_temp'
AS $function$
declare
  job public.email_conversion_photo_jobs%rowtype;
  object_row public.email_conversion_photo_objects%rowtype;
  attachment public.email_attachments%rowtype;
  activity public.activities%rowtype;
  conversion_event public.opportunity_conversion_events%rowtype;
  photo_id uuid;
  expected_path text;
  expected_url_suffix text;
begin
  select * into job
    from public.email_conversion_photo_jobs queued_job
   where queued_job.id = p_job_id
   for update;

  if job.id is null
    or job.status <> 'processing'
    or job.operation <> 'materialize'
    or job.generation is distinct from p_generation
    or job.lease_token is distinct from p_lease_token
    or job.lease_expires_at <= now()
  then
    return false;
  end if;

  select * into object_row
    from public.email_conversion_photo_objects ledger_object
   where ledger_object.job_id = job.id
     and ledger_object.generation = p_generation
     and ledger_object.object_path = p_project_storage_path
   for update;

  if object_row.id is null
    or object_row.state <> 'staged'
    or object_row.job_lease_token is distinct from p_lease_token
  then
    return false;
  end if;

  select * into attachment
    from public.email_attachments source_attachment
   where source_attachment.id = job.email_attachment_id
   for share;
  if attachment.activity_id is not null then
    select * into activity
      from public.activities exact_activity
     where exact_activity.id = attachment.activity_id
     for share;
  end if;
  select * into conversion_event
    from public.opportunity_conversion_events event
   where event.id = job.conversion_event_id;

  if attachment.id is null
    or conversion_event.id is null
    or attachment.company_id is distinct from job.company_id
    or attachment.opportunity_id is distinct from job.opportunity_id
    or attachment.ingest_status <> 'stored'
    or attachment.attribution_status <> 'attributed'
    or attachment.storage_backend <> 'supabase'
    or nullif(btrim(attachment.storage_path), '') is null
    or attachment.content_sha256 is distinct from job.source_content_sha256
    or attachment.verified_size_bytes is distinct from job.source_verified_size_bytes
    or lower(coalesce(attachment.detected_mime_type, '')) not like 'image/%'
    or activity.id is null
    or activity.type is distinct from 'email'
    or activity.company_id is distinct from job.company_id
    or activity.email_connection_id is distinct from attachment.connection_id
    or activity.email_message_id is distinct from attachment.message_id
    or activity.opportunity_id is distinct from job.opportunity_id
    or activity.direction is distinct from 'inbound'
    or coalesce(activity.match_needs_review, false)
    or conversion_event.event_type <> 'converted_to_project'
    or conversion_event.company_id is distinct from job.company_id
    or conversion_event.opportunity_id is distinct from job.opportunity_id
    or conversion_event.project_id is distinct from job.project_id
    or not private.email_conversion_photo_source_is_eligible(attachment.id)
  then
    raise exception 'email conversion photo source changed before completion'
      using errcode = '40001';
  end if;

  expected_path :=
    job.company_id::text || '/' || job.project_id::text || '/email/'
    || job.conversion_event_id::text || '/'
    || job.email_attachment_id::text || '-'
    || left(job.source_content_sha256, 32) || '-g'
    || job.generation::text || '.jpg';
  expected_url_suffix :=
    '/storage/v1/object/public/project-photos/' || expected_path;

  if p_project_storage_path is distinct from expected_path
    or nullif(btrim(p_project_photo_url), '') is null
    or p_project_photo_url !~ '^https://'
    or right(p_project_photo_url, length(expected_url_suffix)) is distinct from expected_url_suffix
    or p_project_content_sha256 !~ '^[0-9a-f]{64}$'
    or p_project_verified_size_bytes is null
    or p_project_verified_size_bytes < 0
    or p_project_verified_size_bytes > 10485760
  then
    raise exception 'email conversion project photo result is invalid'
      using errcode = '23514';
  end if;

  photo_id := job.project_photo_id;
  if photo_id is not null then
    perform 1
      from public.project_photos mapped_photo
     where mapped_photo.id = photo_id
       and mapped_photo.project_id = job.project_id::text
       and mapped_photo.company_id = job.company_id::text
     for update;
    if not found then
      raise exception 'email conversion project photo mapping is invalid'
        using errcode = '23514';
    end if;
  else
    select existing_photo.id into photo_id
      from public.project_photos existing_photo
     where existing_photo.project_id = job.project_id::text
       and existing_photo.company_id = job.company_id::text
       and existing_photo.url = p_project_photo_url
     order by existing_photo.created_at, existing_photo.id
     limit 1
     for update;
  end if;

  if photo_id is null then
    insert into public.project_photos (
      id,
      project_id,
      company_id,
      url,
      thumbnail_url,
      source,
      email_attachment_id,
      origin_sender_email,
      site_visit_id,
      uploaded_by,
      taken_at,
      caption,
      is_client_visible,
      deleted_at,
      created_at
    ) values (
      gen_random_uuid(),
      job.project_id::text,
      job.company_id::text,
      p_project_photo_url,
      p_project_photo_url,
      'email',
      job.email_attachment_id,
      nullif(btrim(coalesce(attachment.from_email, '')), ''),
      null,
      coalesce(conversion_event.actor_user_id::text, 'system'),
      p_occurred_at,
      nullif(btrim(p_filename), ''),
      false,
      null,
      now()
    ) returning id into photo_id;
  end if;

  update public.project_photos photo
     set project_id = job.project_id::text,
         company_id = job.company_id::text,
         url = p_project_photo_url,
         thumbnail_url = p_project_photo_url,
         source = 'email',
         email_attachment_id = job.email_attachment_id,
         origin_sender_email =
           nullif(btrim(coalesce(attachment.from_email, '')), ''),
         site_visit_id = null,
         uploaded_by = coalesce(conversion_event.actor_user_id::text, 'system'),
         taken_at = p_occurred_at,
         caption = nullif(btrim(p_filename), ''),
         is_client_visible = false,
         deleted_at = null
   where photo.id = photo_id;

  update public.email_conversion_photo_objects prior_object
     set project_photo_id = null,
         updated_at = now()
   where prior_object.job_id = job.id
     and prior_object.id <> object_row.id
     and prior_object.project_photo_id = photo_id;

  update public.email_conversion_photo_objects published_object
     set state = 'published',
         project_photo_url = p_project_photo_url,
         project_content_sha256 = p_project_content_sha256,
         project_verified_size_bytes = p_project_verified_size_bytes,
         project_photo_id = photo_id,
         last_error = null,
         published_at = now(),
         deleted_at = null,
         updated_at = now()
   where published_object.id = object_row.id;

  update public.email_conversion_photo_jobs queued_job
     set status = 'complete',
         project_storage_path = p_project_storage_path,
         project_content_sha256 = p_project_content_sha256,
         project_verified_size_bytes = p_project_verified_size_bytes,
         project_photo_id = photo_id,
         last_error = null,
         completed_at = now(),
         lease_owner = null,
         lease_token = null,
         lease_expires_at = null,
         updated_at = now()
   where queued_job.id = job.id;

  return true;
end;
$function$;

-- Backfill: attribute the photos the pipeline already imported as 'other'.
-- Includes the one soft-deleted row -- keeps history honest.
update public.project_photos ph
   set source = 'email',
       email_attachment_id = j.email_attachment_id,
       origin_sender_email = nullif(btrim(coalesce(att.from_email, '')), '')
  from public.email_conversion_photo_jobs j
  left join public.email_attachments att on att.id = j.email_attachment_id
 where j.project_photo_id = ph.id
   and j.operation = 'materialize';
