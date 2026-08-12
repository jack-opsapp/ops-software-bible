ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS expense_id text DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS batch_id text DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS deep_link_type text DEFAULT NULL;
