
-- Add missing columns to roles table
ALTER TABLE roles
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS is_preset boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS company_id uuid REFERENCES companies(id),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

-- Mark existing roles as presets and give them human-readable names/descriptions
UPDATE roles SET
  is_preset = true,
  name = 'Field Crew',
  description = 'Field workers with access to assigned projects, tasks, and schedules.',
  updated_at = now()
WHERE name = 'field_crew';

UPDATE roles SET
  is_preset = true,
  name = 'Office Staff',
  description = 'Office personnel with access to project management, scheduling, and client data.',
  updated_at = now()
WHERE name = 'office_crew';

UPDATE roles SET
  is_preset = true,
  name = 'Admin',
  description = 'Full access to all company settings, team management, and financial data.',
  updated_at = now()
WHERE name = 'admin';

-- Add RLS policy so companies can see preset roles + their own custom roles
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "roles_select" ON roles;
DROP POLICY IF EXISTS "roles_insert" ON roles;
DROP POLICY IF EXISTS "roles_update" ON roles;
DROP POLICY IF EXISTS "roles_delete" ON roles;

-- Everyone can read preset roles + roles belonging to their company
CREATE POLICY "roles_select" ON roles FOR SELECT USING (
  is_preset = true OR company_id IS NOT NULL
);

-- Companies can only insert non-preset roles with their company_id
CREATE POLICY "roles_insert" ON roles FOR INSERT WITH CHECK (
  is_preset = false AND company_id IS NOT NULL
);

-- Companies can only update their own non-preset roles
CREATE POLICY "roles_update" ON roles FOR UPDATE USING (
  is_preset = false AND company_id IS NOT NULL
);

-- Companies can only delete their own non-preset roles
CREATE POLICY "roles_delete" ON roles FOR DELETE USING (
  is_preset = false AND company_id IS NOT NULL
);

