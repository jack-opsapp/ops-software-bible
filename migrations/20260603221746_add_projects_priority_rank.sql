ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS priority_rank double precision;

CREATE INDEX IF NOT EXISTS idx_projects_priority
  ON public.projects (company_id, priority_rank)
  WHERE deleted_at IS NULL;
