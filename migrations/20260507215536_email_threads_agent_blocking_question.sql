ALTER TABLE public.email_threads
  ADD COLUMN IF NOT EXISTS agent_blocking_question jsonb;

COMMENT ON COLUMN public.email_threads.agent_blocking_question IS
  'Phase C escalation when Claude cannot draft without operator input. Shape: {question, options?, asked_at}. NULL when no escalation is pending; cleared when the operator answers.';

CREATE INDEX IF NOT EXISTS idx_email_threads_blocking_question
  ON public.email_threads (company_id)
  WHERE agent_blocking_question IS NOT NULL;

COMMENT ON INDEX public.idx_email_threads_blocking_question IS
  'Partial index for "blocked threads in this company" — drives the NEEDS_INPUT column group and any future operator dashboard.';
