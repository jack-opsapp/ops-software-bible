-- Add is_client_visible column to project_photos to match documented client portal photo filter
-- Bible reference: ops-software-bible/11_CLIENT_PORTAL.md (only photos where is_client_visible = true shown in portal)
-- Consumers: iOS DeckBuilder/PhotoOverlayEditor (write), OPS-Web project-photo-service (read), Client portal (filter)
ALTER TABLE project_photos
  ADD COLUMN IF NOT EXISTS is_client_visible BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_project_photos_client_visible
  ON project_photos(project_id, is_client_visible)
  WHERE deleted_at IS NULL;

COMMENT ON COLUMN project_photos.is_client_visible IS
  'When true, photo is visible in the client portal (PortalPhotoGallery). Defaults false for internal-only.';

