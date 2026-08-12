-- vinyl_ordered_by mirrors projects.created_by — a user reference into
-- auth.users(id). The add_projects_vinyl_order_columns migration added the
-- column as a plain uuid; this adds the FK to match created_by
-- (projects_created_by_fkey) and the schema documented in the bible. Every
-- vinyl_ordered_by value is currently NULL, so the constraint validates
-- instantly. User-approved 2026-05-21.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'projects_vinyl_ordered_by_fkey'
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_vinyl_ordered_by_fkey
      FOREIGN KEY (vinyl_ordered_by) REFERENCES auth.users(id);
  END IF;
END $$;
