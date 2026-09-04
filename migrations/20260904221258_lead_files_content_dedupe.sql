-- Bug 05f0aae6 — "many duplicate photos were uploaded to Mariah Burton's lead".
--
-- Every reply in an email thread re-includes the previous message's inline
-- images. The ingester correctly keys on a PER-MESSAGE identity, so each quote
-- becomes a new row plus a new S3 object. Those rows are TRUE — each records
-- that a specific message carried that attachment. But the identity the
-- OPERATOR sees is the file's CONTENT, not the message. The READ was wrong,
-- not the data, so this changes the read and repairs nothing.
--
-- Measured on the reported lead (2667c10d-…): 29 rows, 9 distinct content
-- hashes; one image appears 10 times across 10 messages.
--
-- Replay-on-drain from the 3-day email freeze was tested and RULED OUT: zero
-- rows on this lead were created 2026-09-01 -> 09-04.
--
-- One row per distinct content, EARLIEST occurrence wins (the message where the
-- customer actually sent it), then the newest-first order the client expects.
-- Signature, return type, column order, volatility, security mode, search_path
-- and every filter are carried over unchanged and were diffed against the live
-- definition before applying; only the row set shrinks. create or replace
-- preserves the ACL. iOS is the only consumer (get_opportunity_lead_files is
-- not referenced in ops-web/src), so every already-shipped build is fixed the
-- moment this lands — no App Store release needed.
--
-- No data repair, deliberately: deleting the 82 redundant rows company-wide
-- would destroy per-message provenance and orphan S3 objects, for 0.18 GiB
-- (~$0.01/month).

create or replace function private.get_opportunity_lead_files(p_opportunity_id uuid)
returns table(id uuid, filename text, mime_type text, source_url text,
              from_email text, ingest_status text,
              occurred_at timestamp with time zone, created_at timestamp with time zone)
language sql
stable
security definer
set search_path to 'pg_catalog', 'pg_temp'
as $function$
  with visible as (
    select
      attachment.id,
      attachment.filename,
      attachment.mime_type,
      case when attachment.ingest_status = 'external' then attachment.source_url else null end as source_url,
      attachment.from_email,
      attachment.ingest_status,
      attachment.occurred_at,
      attachment.created_at,
      coalesce(attachment.content_sha256, attachment.id::text) as content_key
    from public.email_attachments as attachment
    where attachment.opportunity_id = p_opportunity_id
      and attachment.attribution_status = 'attributed'
      and attachment.ingest_status in ('stored', 'external')
      and (
        attachment.ingest_status = 'stored'
        or private.is_safe_https_attachment_url(attachment.source_url)
      )
      and private.current_user_can_view_opportunity_inbox(
            p_opportunity_id, attachment.connection_id)
  ),
  earliest as (
    select distinct on (content_key)
      id, filename, mime_type, source_url, from_email, ingest_status, occurred_at, created_at
    from visible
    order by content_key, occurred_at asc nulls last, created_at asc, id asc
  )
  select id, filename, mime_type, source_url, from_email, ingest_status, occurred_at, created_at
  from earliest
  order by occurred_at desc nulls last, created_at desc, id desc;
$function$;
