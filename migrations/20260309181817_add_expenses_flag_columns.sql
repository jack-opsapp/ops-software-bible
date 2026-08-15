ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS flag_comment text DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS flagged_by uuid REFERENCES public.users(id) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS flagged_at timestamptz DEFAULT NULL;
