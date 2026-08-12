
-- ============================================================
-- Replace 3 legacy roles with 5 correct preset roles
-- ============================================================

-- 0. Drop the unique constraint on name that blocks us
ALTER TABLE roles DROP CONSTRAINT IF EXISTS roles_unique_name;
ALTER TABLE roles DROP CONSTRAINT IF EXISTS roles_name_key;

-- 1. Rename old roles to avoid name conflicts
UPDATE roles SET name = '_legacy_admin' WHERE id = '04249c3f-64c7-43de-9ff0-c41eddd56044';
UPDATE roles SET name = '_legacy_office' WHERE id = 'c92cd886-ff1a-4d21-b8cd-46ff73845837';
UPDATE roles SET name = '_legacy_crew' WHERE id = 'd0b89b3f-2e1c-4626-83c2-8097bf87a1fc';

-- 2. Insert 5 correct preset roles with fixed UUIDs
INSERT INTO roles (id, name, description, is_preset, company_id, hierarchy, updated_at) VALUES
  ('00000000-0000-0000-0000-000000000001', 'Admin', 'Full system access including billing and roles.', true, NULL, 1, now()),
  ('00000000-0000-0000-0000-000000000002', 'Owner', 'Full access. Company settings and integrations.', true, NULL, 2, now()),
  ('00000000-0000-0000-0000-000000000003', 'Office', 'Office staff. Full project and financial access.', true, NULL, 3, now()),
  ('00000000-0000-0000-0000-000000000004', 'Operator', 'Lead tech. Quotes jobs, manages assigned work.', true, NULL, 4, now()),
  ('00000000-0000-0000-0000-000000000005', 'Crew', 'Basic field access. View assigned work only.', true, NULL, 5, now());

-- 3. Remap user_roles from legacy IDs to new preset IDs
UPDATE user_roles SET role_id = '00000000-0000-0000-0000-000000000001'
  WHERE role_id = '04249c3f-64c7-43de-9ff0-c41eddd56044';

UPDATE user_roles SET role_id = '00000000-0000-0000-0000-000000000003'
  WHERE role_id = 'c92cd886-ff1a-4d21-b8cd-46ff73845837';

UPDATE user_roles SET role_id = '00000000-0000-0000-0000-000000000005'
  WHERE role_id = 'd0b89b3f-2e1c-4626-83c2-8097bf87a1fc';

-- 4. Delete old role_permissions for legacy roles
DELETE FROM role_permissions WHERE role_id IN (
  '04249c3f-64c7-43de-9ff0-c41eddd56044',
  'c92cd886-ff1a-4d21-b8cd-46ff73845837',
  'd0b89b3f-2e1c-4626-83c2-8097bf87a1fc'
);

-- 5. Delete legacy roles
DELETE FROM roles WHERE id IN (
  '04249c3f-64c7-43de-9ff0-c41eddd56044',
  'c92cd886-ff1a-4d21-b8cd-46ff73845837',
  'd0b89b3f-2e1c-4626-83c2-8097bf87a1fc'
);

-- 6. Re-add unique constraint (company_id, name)
ALTER TABLE roles ADD CONSTRAINT roles_unique_name UNIQUE (company_id, name);

-- 7. Seed Admin permissions (all 55 permissions, scope=all)
INSERT INTO role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000001', 'projects.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'projects.create', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'projects.edit', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'projects.delete', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'projects.archive', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'projects.assign_team', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'tasks.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'tasks.create', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'tasks.edit', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'tasks.delete', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'tasks.assign', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'tasks.change_status', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'clients.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'clients.create', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'clients.edit', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'clients.delete', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'calendar.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'calendar.create', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'calendar.edit', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'calendar.delete', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'job_board.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'job_board.manage_sections', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'estimates.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'estimates.create', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'estimates.edit', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'estimates.delete', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'estimates.send', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'invoices.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'invoices.create', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'invoices.edit', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'invoices.delete', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'invoices.send', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'invoices.record_payment', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'pipeline.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'pipeline.manage', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'pipeline.configure_stages', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'products.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'products.manage', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'expenses.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'expenses.create', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'expenses.edit', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'expenses.approve', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'accounting.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'accounting.manage_connections', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'inventory.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'inventory.manage', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'inventory.import', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'photos.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'photos.upload', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'photos.annotate', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'photos.delete', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'documents.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'documents.manage_templates', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'team.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'team.manage', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'team.assign_roles', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'map.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'map.view_crew_locations', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'notifications.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'notifications.manage_preferences', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'settings.company', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'settings.billing', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'settings.integrations', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'settings.preferences', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'portal.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'portal.manage_branding', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'reports.view', 'all');

-- 8. Seed Owner permissions (everything except billing + assign_roles)
INSERT INTO role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000002', 'projects.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'projects.create', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'projects.edit', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'projects.delete', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'projects.archive', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'projects.assign_team', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'tasks.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'tasks.create', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'tasks.edit', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'tasks.delete', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'tasks.assign', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'tasks.change_status', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'clients.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'clients.create', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'clients.edit', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'clients.delete', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'calendar.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'calendar.create', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'calendar.edit', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'calendar.delete', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'job_board.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'job_board.manage_sections', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'estimates.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'estimates.create', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'estimates.edit', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'estimates.delete', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'estimates.send', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'invoices.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'invoices.create', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'invoices.edit', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'invoices.delete', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'invoices.send', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'invoices.record_payment', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'pipeline.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'pipeline.manage', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'pipeline.configure_stages', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'products.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'products.manage', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'expenses.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'expenses.create', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'expenses.edit', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'expenses.approve', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'accounting.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'accounting.manage_connections', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'inventory.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'inventory.manage', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'inventory.import', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'photos.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'photos.upload', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'photos.annotate', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'photos.delete', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'documents.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'documents.manage_templates', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'team.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'team.manage', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'map.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'map.view_crew_locations', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'notifications.view', 'own'),
  ('00000000-0000-0000-0000-000000000002', 'notifications.manage_preferences', 'own'),
  ('00000000-0000-0000-0000-000000000002', 'settings.company', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'settings.integrations', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'settings.preferences', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'portal.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'portal.manage_branding', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'reports.view', 'all');

-- 9. Seed Office permissions
INSERT INTO role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000003', 'projects.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'projects.create', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'projects.edit', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'projects.archive', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'projects.assign_team', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'tasks.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'tasks.create', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'tasks.edit', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'tasks.delete', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'tasks.assign', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'tasks.change_status', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'clients.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'clients.create', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'clients.edit', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'calendar.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'calendar.create', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'calendar.edit', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'calendar.delete', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'job_board.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'job_board.manage_sections', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'estimates.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'estimates.create', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'estimates.edit', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'estimates.delete', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'estimates.send', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'invoices.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'invoices.create', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'invoices.edit', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'invoices.delete', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'invoices.send', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'invoices.record_payment', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'pipeline.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'pipeline.manage', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'products.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'products.manage', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'expenses.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'expenses.create', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'expenses.edit', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'expenses.approve', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'accounting.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'inventory.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'inventory.manage', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'photos.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'photos.upload', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'photos.annotate', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'photos.delete', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'documents.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'team.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'map.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'map.view_crew_locations', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'notifications.view', 'own'),
  ('00000000-0000-0000-0000-000000000003', 'notifications.manage_preferences', 'own'),
  ('00000000-0000-0000-0000-000000000003', 'settings.preferences', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'portal.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'reports.view', 'all');

-- 10. Seed Operator permissions
INSERT INTO role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000004', 'projects.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'projects.create', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'projects.edit', 'assigned'),
  ('00000000-0000-0000-0000-000000000004', 'tasks.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'tasks.create', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'tasks.edit', 'assigned'),
  ('00000000-0000-0000-0000-000000000004', 'tasks.change_status', 'assigned'),
  ('00000000-0000-0000-0000-000000000004', 'clients.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'clients.create', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'calendar.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'calendar.create', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'calendar.edit', 'own'),
  ('00000000-0000-0000-0000-000000000004', 'job_board.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'estimates.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'estimates.create', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'estimates.edit', 'own'),
  ('00000000-0000-0000-0000-000000000004', 'invoices.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'products.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'expenses.view', 'own'),
  ('00000000-0000-0000-0000-000000000004', 'expenses.create', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'expenses.edit', 'own'),
  ('00000000-0000-0000-0000-000000000004', 'photos.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'photos.upload', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'photos.annotate', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'photos.delete', 'own'),
  ('00000000-0000-0000-0000-000000000004', 'documents.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'team.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'map.view', 'all'),
  ('00000000-0000-0000-0000-000000000004', 'notifications.view', 'own'),
  ('00000000-0000-0000-0000-000000000004', 'notifications.manage_preferences', 'own'),
  ('00000000-0000-0000-0000-000000000004', 'settings.preferences', 'all');

-- 11. Seed Crew permissions
INSERT INTO role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000005', 'projects.view', 'assigned'),
  ('00000000-0000-0000-0000-000000000005', 'tasks.view', 'assigned'),
  ('00000000-0000-0000-0000-000000000005', 'tasks.edit', 'assigned'),
  ('00000000-0000-0000-0000-000000000005', 'tasks.change_status', 'assigned'),
  ('00000000-0000-0000-0000-000000000005', 'clients.view', 'assigned'),
  ('00000000-0000-0000-0000-000000000005', 'calendar.view', 'own'),
  ('00000000-0000-0000-0000-000000000005', 'job_board.view', 'assigned'),
  ('00000000-0000-0000-0000-000000000005', 'expenses.view', 'own'),
  ('00000000-0000-0000-0000-000000000005', 'expenses.create', 'all'),
  ('00000000-0000-0000-0000-000000000005', 'expenses.edit', 'own'),
  ('00000000-0000-0000-0000-000000000005', 'photos.view', 'assigned'),
  ('00000000-0000-0000-0000-000000000005', 'photos.upload', 'all'),
  ('00000000-0000-0000-0000-000000000005', 'photos.annotate', 'all'),
  ('00000000-0000-0000-0000-000000000005', 'map.view', 'all'),
  ('00000000-0000-0000-0000-000000000005', 'notifications.view', 'own'),
  ('00000000-0000-0000-0000-000000000005', 'notifications.manage_preferences', 'own'),
  ('00000000-0000-0000-0000-000000000005', 'settings.preferences', 'all');

