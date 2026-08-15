-- Deck Builder vinyl ordering — project-level order marker.
-- iOS (feat/vinyl-auto-order, commit 2128d875) reads/writes these via
-- SupabaseProjectDTO; ProjectVinylOrderMarker is the local SwiftData
-- projection. Columns are additive + nullable with a default so older
-- iOS builds keep decoding `projects` rows during phased rollout, and a
-- full-DTO update that sends an explicit NULL does not violate NOT NULL.
ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS vinyl_order_status text DEFAULT 'not_ordered',
  ADD COLUMN IF NOT EXISTS vinyl_ordered_at  timestamptz,
  ADD COLUMN IF NOT EXISTS vinyl_ordered_by  uuid;

-- Closed enum guard matching iOS ProjectVinylOrderStatus. NULL is allowed
-- so an outbound update that omits/nulls the field is treated as
-- not_ordered by iOS rather than rejected by Postgres.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'projects_vinyl_order_status_check'
  ) THEN
    ALTER TABLE public.projects
      ADD CONSTRAINT projects_vinyl_order_status_check
      CHECK (vinyl_order_status IS NULL
             OR vinyl_order_status IN ('not_ordered', 'ordered'));
  END IF;
END $$;

COMMENT ON COLUMN public.projects.vinyl_order_status IS
  'Deck Builder vinyl order marker: not_ordered | ordered. Default not_ordered.';
COMMENT ON COLUMN public.projects.vinyl_ordered_at IS
  'When the vinyl order was placed from Deck Builder.';
COMMENT ON COLUMN public.projects.vinyl_ordered_by IS
  'User who placed the vinyl order from Deck Builder.';
