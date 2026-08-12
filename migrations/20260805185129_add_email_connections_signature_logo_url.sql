alter table public.email_connections add column if not exists signature_logo_url text;
comment on column public.email_connections.signature_logo_url is 'Custom logo for the email signature, distinct from companies.logo_url. Null = fall back to the company logo. Uploaded via the identity settings surface; hosted on the app''s existing image storage.';
