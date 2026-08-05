-- Applied to prod 2026-08-03 via MCP (name: add_email_connections_outreach_subject).
-- Per-mailbox subject line for NEW-thread lead outreach drafts (contact-form
-- leads open a fresh thread, so there is no inbound subject to reply to).
-- Null = not configured; the engine falls back to the built-in default and the
-- sender-identity gate holds outreach until the operator confirms identity.
-- See 07_SPECIALIZED_FEATURES.md § Sender Identity & Outreach Settings (2026-08-05).
alter table public.email_connections add column if not exists outreach_subject text;
comment on column public.email_connections.outreach_subject is 'Operator-configured subject line for NEW-thread lead outreach drafts (e.g. contact-form leads). Null = not configured; engine falls back to the built-in default and the identity gate holds outreach until the operator confirms identity settings.';
