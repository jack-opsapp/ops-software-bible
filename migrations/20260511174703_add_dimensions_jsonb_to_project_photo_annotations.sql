ALTER TABLE project_photo_annotations
  ADD COLUMN IF NOT EXISTS dimensions jsonb;

COMMENT ON COLUMN project_photo_annotations.dimensions IS
  'Structured measurement annotations from LiDAR/AR capture per spec 2026-05-10. NULL for legacy PencilKit-only annotations.';
