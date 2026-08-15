-- Add updated_at to project_photos so iOS incremental sync (.gte("updated_at", since))
-- can pull deltas. Mirrors the project_notes convention: backfill from created_at,
-- default now(), NOT NULL, and a BEFORE UPDATE trigger using update_timestamp().
ALTER TABLE public.project_photos ADD COLUMN IF NOT EXISTS updated_at timestamptz;
UPDATE public.project_photos SET updated_at = COALESCE(created_at, now()) WHERE updated_at IS NULL;
ALTER TABLE public.project_photos ALTER COLUMN updated_at SET DEFAULT now();
ALTER TABLE public.project_photos ALTER COLUMN updated_at SET NOT NULL;
DROP TRIGGER IF EXISTS update_project_photos_timestamp ON public.project_photos;
CREATE TRIGGER update_project_photos_timestamp
  BEFORE UPDATE ON public.project_photos
  FOR EACH ROW EXECUTE FUNCTION update_timestamp();
