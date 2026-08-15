BEGIN;

-- New keys (idempotent — INSERTs gated by ON CONFLICT)
-- Owner / Admin / Office: full read+manage; Operator: read; Crew: stock.adjust only.
--
-- Owner = 00000000-0000-0000-0000-000000000002
-- Admin = 00000000-0000-0000-0000-000000000001
-- Office = 00000000-0000-0000-0000-000000000003
-- Operator = 00000000-0000-0000-0000-000000000004
-- Crew = 00000000-0000-0000-0000-000000000005

-- catalog.stock.adjust — Crew, Office, Owner, Admin
INSERT INTO public.role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000005', 'catalog.stock.adjust', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'catalog.stock.adjust', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'catalog.stock.adjust', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'catalog.stock.adjust', 'all')
ON CONFLICT DO NOTHING;

-- catalog.products.view — Operator, Office, Owner, Admin
INSERT INTO public.role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000004', 'catalog.products.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'catalog.products.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'catalog.products.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'catalog.products.view', 'all')
ON CONFLICT DO NOTHING;

-- catalog.orders.view — Operator, Office, Owner, Admin
INSERT INTO public.role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000004', 'catalog.orders.view', 'all'),
  ('00000000-0000-0000-0000-000000000003', 'catalog.orders.view', 'all'),
  ('00000000-0000-0000-0000-000000000002', 'catalog.orders.view', 'all'),
  ('00000000-0000-0000-0000-000000000001', 'catalog.orders.view', 'all')
ON CONFLICT DO NOTHING;

-- Operator + Crew need catalog.view (not yet granted)
INSERT INTO public.role_permissions (role_id, permission, scope) VALUES
  ('00000000-0000-0000-0000-000000000004', 'catalog.view', 'all'),
  ('00000000-0000-0000-0000-000000000005', 'catalog.view', 'all')
ON CONFLICT DO NOTHING;

COMMIT;
