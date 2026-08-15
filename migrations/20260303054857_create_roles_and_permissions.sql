
-- 1. Create roles table
CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    hierarchy INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Create user_roles table (links users to roles)
CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(user_id)
);

-- 3. Create role_permissions table
CREATE TABLE role_permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission TEXT NOT NULL,
    scope TEXT NOT NULL DEFAULT 'all',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(role_id, permission)
);

-- 4. Seed the three roles (hierarchy: higher = more powerful)
INSERT INTO roles (name, hierarchy) VALUES
    ('admin', 100),
    ('office_crew', 50),
    ('field_crew', 10);

-- 5. Seed admin permissions (full access to everything)
INSERT INTO role_permissions (role_id, permission, scope)
SELECT r.id, p.permission, p.scope
FROM roles r
CROSS JOIN (VALUES
    ('projects.create', 'all'),
    ('projects.edit', 'all'),
    ('projects.view', 'all'),
    ('tasks.create', 'all'),
    ('tasks.edit', 'all'),
    ('tasks.view', 'all'),
    ('tasks.delete', 'all'),
    ('tasks.change_status', 'all'),
    ('clients.create', 'all'),
    ('clients.edit', 'all'),
    ('estimates.create', 'all'),
    ('expenses.create', 'all'),
    ('calendar.view', 'all'),
    ('calendar.edit', 'all'),
    ('team.view', 'all'),
    ('team.manage', 'all'),
    ('settings.company', 'all'),
    ('settings.billing', 'all'),
    ('inventory.view', 'all'),
    ('pipeline.view', 'all'),
    ('pipeline.manage', 'all'),
    ('job_board.manage_sections', 'all')
) AS p(permission, scope)
WHERE r.name = 'admin';

-- 6. Seed office_crew permissions (can view/edit most things, no billing/team manage)
INSERT INTO role_permissions (role_id, permission, scope)
SELECT r.id, p.permission, p.scope
FROM roles r
CROSS JOIN (VALUES
    ('projects.create', 'all'),
    ('projects.edit', 'all'),
    ('projects.view', 'all'),
    ('tasks.create', 'all'),
    ('tasks.edit', 'all'),
    ('tasks.view', 'all'),
    ('tasks.delete', 'all'),
    ('tasks.change_status', 'all'),
    ('clients.create', 'all'),
    ('clients.edit', 'all'),
    ('estimates.create', 'all'),
    ('expenses.create', 'all'),
    ('calendar.view', 'all'),
    ('calendar.edit', 'all'),
    ('team.view', 'all'),
    ('settings.company', 'all'),
    ('inventory.view', 'all'),
    ('pipeline.view', 'all'),
    ('job_board.manage_sections', 'all')
) AS p(permission, scope)
WHERE r.name = 'office_crew';

-- 7. Seed field_crew permissions (assigned-scope only, limited actions)
INSERT INTO role_permissions (role_id, permission, scope)
SELECT r.id, p.permission, p.scope
FROM roles r
CROSS JOIN (VALUES
    ('projects.view', 'assigned'),
    ('tasks.view', 'assigned'),
    ('tasks.change_status', 'assigned'),
    ('calendar.view', 'assigned'),
    ('expenses.create', 'own'),
    ('inventory.view', 'assigned')
) AS p(permission, scope)
WHERE r.name = 'field_crew';

-- 8. Backfill user_roles for all existing users based on their role column
INSERT INTO user_roles (user_id, role_id)
SELECT u.id, r.id
FROM users u
JOIN roles r ON r.name = u.role
WHERE u.role IS NOT NULL
ON CONFLICT (user_id) DO NOTHING;

