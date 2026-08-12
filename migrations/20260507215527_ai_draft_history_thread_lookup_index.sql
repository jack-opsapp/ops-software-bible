CREATE INDEX IF NOT EXISTS idx_ai_draft_history_thread_lookup
  ON public.ai_draft_history (connection_id, thread_id, created_at DESC);

COMMENT ON INDEX public.idx_ai_draft_history_thread_lookup IS
  'Supports inbox v2 phaseC join: latest draft row per (connection_id, thread_id). thread_id is the provider thread id, matching email_threads.provider_thread_id.';
