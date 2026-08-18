-- Email-origin provenance for pipeline-imported project photos.
-- Nullable + additive: invisible to deployed iOS builds (additive-only
-- sync constraint) and to the deployed web bundle.
alter table public.project_photos
  add column if not exists email_attachment_id uuid
    references public.email_attachments(id) on delete set null,
  add column if not exists origin_sender_email text;

create index if not exists project_photos_email_attachment_idx
  on public.project_photos (email_attachment_id)
  where email_attachment_id is not null;
