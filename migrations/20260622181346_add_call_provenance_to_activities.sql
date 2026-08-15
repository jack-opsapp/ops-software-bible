-- Around-call lead capture (iOS feature 154cb8a3): additive, nullable call
-- provenance columns on activities. NO constraints / NO defaults / NO NOT NULL
-- so the iOS<->Supabase sync contract stays intact (additive-only).
ALTER TABLE public.activities
  ADD COLUMN IF NOT EXISTS call_source     text,
  ADD COLUMN IF NOT EXISTS caller_number   text,
  ADD COLUMN IF NOT EXISTS call_started_at timestamptz;

COMMENT ON COLUMN public.activities.call_source IS
  'Around-call provenance from the OPS iOS client: how the call log was captured (post_call_prompt | contact_card | fab_picker | fab_manual | app_shortcut). Nullable, additive-only for iOS sync.';
COMMENT ON COLUMN public.activities.caller_number IS
  'Phone number involved in a logged call, stored as normalized digits for dedup. Nullable.';
COMMENT ON COLUMN public.activities.call_started_at IS
  'Best-effort timestamp the call started, captured around-call by the OPS iOS client. Nullable.';
