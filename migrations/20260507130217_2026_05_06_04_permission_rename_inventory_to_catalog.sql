BEGIN;

UPDATE public.role_permissions SET permission = 'catalog.view'    WHERE permission = 'inventory.view';
UPDATE public.role_permissions SET permission = 'catalog.manage'  WHERE permission = 'inventory.manage';
UPDATE public.role_permissions SET permission = 'catalog.import'  WHERE permission = 'inventory.import';

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
