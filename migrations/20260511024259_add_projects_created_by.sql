ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_projects_created_by_created_at
  ON public.projects (created_by, created_at DESC)
  WHERE deleted_at IS NULL;

COMMENT ON COLUMN public.projects.created_by IS
  'User who created the project. Populated by app on insert. NULL for projects created before 2026-05-10.';
