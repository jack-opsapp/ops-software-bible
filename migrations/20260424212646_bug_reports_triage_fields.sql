
alter table public.bug_reports
  add column if not exists requires_human_review boolean not null default false,
  add column if not exists human_review_reason text,
  add column if not exists fix_branch text,
  add column if not exists fix_pr_url text,
  add column if not exists fix_commit text,
  add column if not exists fix_notes text,
  add column if not exists claimed_at timestamptz,
  add column if not exists fixed_at timestamptz;

comment on column public.bug_reports.requires_human_review is
  'Set true when the scheduled triage agent determines reporter follow-up is required, or when the reporter explicitly flags at submission time. Agents skip rows where this is true.';
comment on column public.bug_reports.human_review_reason is
  'Short explanation of why human input is needed. Populated by the triage agent or by the form toggle (in which case it is a generic reporter-flagged marker).';
comment on column public.bug_reports.fix_branch is 'Branch name the fix was committed on.';
comment on column public.bug_reports.fix_pr_url is 'Pull request URL if the fix was opened as a PR.';
comment on column public.bug_reports.fix_commit is 'Commit SHA of the fix.';
comment on column public.bug_reports.fix_notes is 'Agent notes describing the fix approach, edge cases considered, and verification steps.';
comment on column public.bug_reports.claimed_at is 'Set when an agent claims the bug for processing — used to prevent double-claiming across concurrent runs.';
comment on column public.bug_reports.fixed_at is 'Set when the agent commits a fix.';

create index if not exists idx_bug_reports_triage_queue
  on public.bug_reports (platform, status, requires_human_review, claimed_at)
  where status in ('new', 'triaged');

