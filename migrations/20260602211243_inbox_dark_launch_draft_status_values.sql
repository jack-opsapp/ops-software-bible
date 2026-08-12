alter table public.ai_draft_history
  drop constraint if exists ai_draft_history_status_check;

alter table public.ai_draft_history
  add constraint ai_draft_history_status_check
  check (status = any (array[
    'drafted', 'sent', 'discarded', 'auto_drafted', 'superseded',
    'sent_from_mailbox', 'discarded_in_mailbox'
  ]));
