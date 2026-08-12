-- Adjusted from spec: real schema uses role_permissions(role_id, permission text), not permission_keys.
-- Audit confirmed Owner/Admin/Office already have both products.view + products.manage.
-- Operator + Unassigned are intentionally not in the products spec scope.
-- ONLY GAP: Crew needs view-only.

INSERT INTO role_permissions (role_id, permission)
SELECT r.id, 'products.view'
FROM roles r
WHERE r.name = 'Crew'
  AND r.is_preset = TRUE
  AND NOT EXISTS (
    SELECT 1 FROM role_permissions rp
    WHERE rp.role_id = r.id AND rp.permission = 'products.view'
  );
