-- Seed permissions used by the new permission-based recipient lookup.
-- Without these, switching the iOS notification dispatch from role-filter to
-- users_with_permission(...) would return zero recipients for time-off and
-- inventory alerts and silently break those notifications.
--
-- Granted to the Admin / Owner / Office preset roles only, scope 'all'.
-- Operator and Crew remain ungranted — companies that want to delegate these
-- to a custom role or per-user override can do so without touching presets.

insert into public.role_permissions (role_id, permission, scope)
select r.id, 'time_off.approve', 'all'
from public.roles r
where r.is_preset = true
  and r.name in ('Admin','Owner','Office')
on conflict do nothing;

insert into public.role_permissions (role_id, permission, scope)
select r.id, 'inventory.manage', 'all'
from public.roles r
where r.is_preset = true
  and r.name in ('Admin','Owner','Office')
on conflict do nothing;
