-- SPEC Phase 1 — Migration 8/8: Storage bucket + RLS for intake uploads
-- Source spec: ops-software-bible/SPEC/02_DATA_MODEL.md § Supabase Storage configuration
-- Bucket: spec-intake. Not public. 25MB per file. MIME-whitelist. Signed URLs 24h TTL (set in app code).
-- RLS: operators only. Customer uploads use a server-issued signed upload URL via a server route.

-- Insert bucket row. Supabase storage stores bucket metadata in storage.buckets.
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) values (
  'spec-intake',
  'spec-intake',
  false,
  26214400,                                        -- 25 MB in bytes
  array[
    'application/pdf',
    'image/png',
    'image/jpeg',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Operator-only read/write/delete. Customer uploads go through a server route that
-- issues a narrow signed upload URL (operator effectively writes on the customer's behalf).
create policy "spec-intake read operator only" on storage.objects
  for select using (
    bucket_id = 'spec-intake'
    and private.is_spec_operator()
  );

create policy "spec-intake insert operator only" on storage.objects
  for insert with check (
    bucket_id = 'spec-intake'
    and private.is_spec_operator()
  );

create policy "spec-intake update operator only" on storage.objects
  for update using (
    bucket_id = 'spec-intake'
    and private.is_spec_operator()
  )
  with check (
    bucket_id = 'spec-intake'
    and private.is_spec_operator()
  );

create policy "spec-intake delete operator only" on storage.objects
  for delete using (
    bucket_id = 'spec-intake'
    and private.is_spec_operator()
  );
