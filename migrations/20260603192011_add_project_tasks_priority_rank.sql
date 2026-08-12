ALTER TABLE public.project_tasks
  ADD COLUMN IF NOT EXISTS priority_rank double precision;

CREATE INDEX IF NOT EXISTS idx_project_tasks_priority
  ON public.project_tasks (company_id, priority_rank)
  WHERE deleted_at IS NULL;
