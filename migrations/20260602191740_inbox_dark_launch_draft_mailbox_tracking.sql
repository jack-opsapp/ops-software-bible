alter table public.ai_draft_history
  add column if not exists mailbox_draft_id text;

comment on column public.ai_draft_history.mailbox_draft_id is
  'Provider draft id (Gmail draft id / M365 message id) when this AI draft was placed in the user mailbox Drafts folder. NULL = DB-only draft (never pushed to the mailbox).';

create index if not exists ai_draft_history_mailbox_pending_idx
  on public.ai_draft_history (connection_id, thread_id)
  where mailbox_draft_id is not null and status = 'auto_drafted';
