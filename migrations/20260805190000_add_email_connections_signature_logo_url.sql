-- Applied to prod 2026-08-05 via MCP (name: add_email_connections_signature_logo_url).
-- Filename timestamp is approximate; authoritative version is the MCP migration
-- ledger entry of the same name. Custom signature logo, distinct from
-- companies.logo_url; null = fall back to the company logo. See
-- 07_SPECIALIZED_FEATURES.md § Sender Identity & Outreach Settings (2026-08-05).
alter table public.email_connections add column if not exists signature_logo_url text;
comment on column public.email_connections.signature_logo_url is 'Custom logo for the email signature, distinct from companies.logo_url. Null = fall back to the company logo. Uploaded via the identity settings surface; hosted on the app''s existing image storage.';
