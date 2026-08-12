alter table public.ai_draft_history
  add column if not exists mailbox_draft_cleanup_at timestamptz;

comment on column public.ai_draft_history.mailbox_draft_cleanup_at is
  'Set when the terminal-orphan sweep settled the provider draft named by mailbox_draft_id (deleted, already gone, or intentionally left in place). NULL means unresolved — the sweep will read it from the provider.';

create index if not exists ai_draft_history_mailbox_cleanup_pending_idx
  on public.ai_draft_history (connection_id, created_at desc)
  where mailbox_draft_id is not null
    and mailbox_draft_cleanup_at is null
    and status in ('sent_from_mailbox', 'superseded');
