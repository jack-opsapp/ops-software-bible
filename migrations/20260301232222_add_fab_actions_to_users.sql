ALTER TABLE users
ADD COLUMN IF NOT EXISTS fab_actions text[] DEFAULT NULL;

COMMENT ON COLUMN users.fab_actions IS 'User-customized FAB action IDs and order. NULL = default set.';
