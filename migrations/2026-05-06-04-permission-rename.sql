-- 2026-05-06-04-permission-rename.sql
-- Rename inventory.* permissions to catalog.* and add two new permissions
-- for the configurable-Product authoring layer and for orders.
--
-- Coordinated with iOS Phase 12 callsite renames in the same release.
-- ops-web reads role_permissions directly and will pick up the new keys
-- on its next page render — its UI references inventory.* in code that
-- will be replaced in the named OPS-Web follow-up session. Until then,
-- ops-web's gates return false; rebuild the gating logic against
-- catalog.* in that session.

BEGIN;

-- Rename existing permission strings on role_permissions.
UPDATE public.role_permissions SET permission = 'catalog.view'    WHERE permission = 'inventory.view';
UPDATE public.role_permissions SET permission = 'catalog.manage'  WHERE permission = 'inventory.manage';
UPDATE public.role_permissions SET permission = 'catalog.import'  WHERE permission = 'inventory.import';

-- Add catalog.products.manage and catalog.orders.manage to roles that have
-- catalog.manage (Owner, Admin, etc.).
INSERT INTO public.role_permissions (role_id, permission, scope)
SELECT DISTINCT role_id, 'catalog.products.manage', scope
FROM public.role_permissions
WHERE permission = 'catalog.manage'
ON CONFLICT DO NOTHING;

INSERT INTO public.role_permissions (role_id, permission, scope)
SELECT DISTINCT role_id, 'catalog.orders.manage', scope
FROM public.role_permissions
WHERE permission = 'catalog.manage'
ON CONFLICT DO NOTHING;

COMMIT;
