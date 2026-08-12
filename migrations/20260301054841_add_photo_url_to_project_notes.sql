ALTER TABLE project_notes ADD COLUMN photo_url TEXT DEFAULT NULL;
CREATE INDEX idx_project_notes_photo_url ON project_notes(photo_url) WHERE photo_url IS NOT NULL;
