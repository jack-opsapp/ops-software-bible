-- Applied to prod 2026-08-02 via MCP (name: add_email_connections_outreach_subject).
-- Part of the sender-identity fix (bug 4da75e71): per-mailbox subject line for
-- NEW-thread lead outreach drafts. Null = not configured; engine falls back to
-- the built-in default and the identity gate holds outreach until the operator
-- confirms identity settings.
alter table public.email_connections add column if not exists outreach_subject text;
comment on column public.email_connections.outreach_subject is 'Operator-configured subject line for NEW-thread lead outreach drafts (e.g. contact-form leads). Null = not configured; engine falls back to the built-in default and the identity gate holds outreach until the operator confirms identity settings.';
