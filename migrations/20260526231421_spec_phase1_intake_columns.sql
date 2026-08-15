alter table public.spec_projects
  add column if not exists intake_token_hash text,
  add column if not exists intake_token_issued_at timestamptz,
  add column if not exists intake_files jsonb not null default '[]'::jsonb,
  add column if not exists regulated_workflow_flagged_at timestamptz,
  add column if not exists regulated_workflow_flags jsonb;

create unique index if not exists spec_projects_intake_token_hash_idx
  on public.spec_projects (intake_token_hash)
  where intake_token_hash is not null;

create index if not exists spec_projects_regulated_workflow_idx
  on public.spec_projects (regulated_workflow_flagged_at)
  where regulated_workflow_flagged_at is not null;
