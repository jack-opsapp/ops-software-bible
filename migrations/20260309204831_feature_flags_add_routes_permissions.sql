
ALTER TABLE feature_flags
  ADD COLUMN IF NOT EXISTS routes text[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS permissions text[] DEFAULT '{}';

UPDATE feature_flags SET
  routes = ARRAY['/pipeline'],
  permissions = ARRAY['pipeline.view', 'pipeline.manage', 'pipeline.configure_stages']
WHERE slug = 'pipeline';

UPDATE feature_flags SET
  routes = ARRAY['/accounting'],
  permissions = ARRAY['accounting.view', 'accounting.manage_connections']
WHERE slug = 'accounting';

