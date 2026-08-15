ALTER TABLE notifications
  ADD COLUMN IF NOT EXISTS persistent BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS action_url TEXT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS action_label TEXT DEFAULT NULL;

COMMENT ON COLUMN notifications.persistent IS 'If true, notification cannot be dismissed — stays until resolved programmatically';
COMMENT ON COLUMN notifications.action_url IS 'Optional deep-link URL for click-through (e.g. /projects/abc)';
COMMENT ON COLUMN notifications.action_label IS 'Optional button label for action (e.g. View Results)';
