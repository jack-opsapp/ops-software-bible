create table public.spec_internal_notes (
  id uuid primary key default gen_random_uuid(),
  spec_project_id uuid not null
    references public.spec_projects(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  created_by_user_id uuid not null
    references public.users(id) on delete set null,
  is_test boolean not null default false
);

create index spec_internal_notes_project_idx
  on public.spec_internal_notes (spec_project_id, created_at desc);

alter table public.spec_internal_notes enable row level security;

create policy "spec_internal_notes operator all"
  on public.spec_internal_notes
  for all
  using (private.is_spec_operator())
  with check (private.is_spec_operator());

grant select, insert, update, delete on public.spec_internal_notes to service_role;
