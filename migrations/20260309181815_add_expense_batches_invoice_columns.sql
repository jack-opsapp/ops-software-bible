ALTER TABLE public.expense_batches
  ADD COLUMN IF NOT EXISTS parent_batch_id uuid REFERENCES public.expense_batches(id) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS amendment_number integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_notes text DEFAULT NULL;
