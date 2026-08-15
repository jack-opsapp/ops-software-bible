-- Calendar scope upgrades ride the Gmail OAuth pair as their own bound
-- source. 'calendar' states bind to one exact connection row exactly like
-- 'alert' reconnects do, so the callback can never widen a different
-- mailbox's grant. Shape rule: bound sources carry a connection + mailbox;
-- wizard states carry neither.

alter table public.email_oauth_states
  drop constraint email_oauth_states_source_check;
alter table public.email_oauth_states
  add constraint email_oauth_states_source_check
  check (source = any (array['wizard'::text, 'alert'::text, 'calendar'::text]));

alter table public.email_oauth_states
  drop constraint email_oauth_states_check1;
alter table public.email_oauth_states
  add constraint email_oauth_states_check1
  check (
    (
      source = any (array['alert'::text, 'calendar'::text])
      and connection_id is not null
      and expected_email is not null
      and expected_email = lower(btrim(expected_email))
      and expected_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    )
    or (
      source = 'wizard'::text
      and connection_id is null
      and expected_email is null
    )
  );
