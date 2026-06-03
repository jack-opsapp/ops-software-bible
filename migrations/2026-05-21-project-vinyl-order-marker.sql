-- Project-level Vinyl Order marker.
-- Marker-only v1: no catalog order, inventory deduction, recipe resolution,
-- or material snapshot is created by these fields.

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS vinyl_order_status text NOT NULL DEFAULT 'not_ordered',
  ADD COLUMN IF NOT EXISTS vinyl_ordered_at timestamptz,
  ADD COLUMN IF NOT EXISTS vinyl_ordered_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

DO $$
BEGIN
  ALTER TABLE public.projects
    ADD CONSTRAINT projects_vinyl_order_status_check
    CHECK (vinyl_order_status IN ('not_ordered', 'ordered'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_projects_company_vinyl_order_status
  ON public.projects(company_id, vinyl_order_status)
  WHERE deleted_at IS NULL;

COMMENT ON COLUMN public.projects.vinyl_order_status IS
  'Deck Builder vinyl order marker. Marker-only v1: not_ordered or ordered.';
COMMENT ON COLUMN public.projects.vinyl_ordered_at IS
  'Timestamp when a user marked the project vinyl as ordered.';
COMMENT ON COLUMN public.projects.vinyl_ordered_by IS
  'auth.users id of the user who marked project vinyl as ordered.';
