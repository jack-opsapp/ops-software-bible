
-- 1. Drop all old constraints first
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_user_type_check;
ALTER TABLE public.projects DROP CONSTRAINT IF EXISTS projects_status_check;
ALTER TABLE public.project_tasks DROP CONSTRAINT IF EXISTS project_tasks_status_check;

-- 2. Migrate existing data to lowercase
UPDATE public.users SET role = 'admin' WHERE role = 'Admin';
UPDATE public.users SET role = 'office_crew' WHERE role = 'Office Crew';
UPDATE public.users SET role = 'field_crew' WHERE role = 'Field Crew';

UPDATE public.users SET user_type = 'employee' WHERE user_type = 'Employee';
UPDATE public.users SET user_type = 'company' WHERE user_type = 'Company';
UPDATE public.users SET user_type = 'client' WHERE user_type = 'Client';
UPDATE public.users SET user_type = 'admin' WHERE user_type = 'Admin';

UPDATE public.projects SET status = 'rfq' WHERE status = 'RFQ';
UPDATE public.projects SET status = 'estimated' WHERE status = 'Estimated';
UPDATE public.projects SET status = 'accepted' WHERE status = 'Accepted';
UPDATE public.projects SET status = 'in_progress' WHERE status = 'In Progress';
UPDATE public.projects SET status = 'completed' WHERE status = 'Completed';
UPDATE public.projects SET status = 'closed' WHERE status = 'Closed';
UPDATE public.projects SET status = 'archived' WHERE status = 'Archived';

UPDATE public.project_tasks SET status = 'booked' WHERE status = 'Booked';
UPDATE public.project_tasks SET status = 'in_progress' WHERE status = 'In Progress';
UPDATE public.project_tasks SET status = 'completed' WHERE status = 'Completed';
UPDATE public.project_tasks SET status = 'cancelled' WHERE status = 'Cancelled';

-- 3. Add new lowercase constraints
ALTER TABLE public.users ADD CONSTRAINT users_role_check 
  CHECK (role = ANY(ARRAY['admin', 'office_crew', 'field_crew']));

ALTER TABLE public.users ADD CONSTRAINT users_user_type_check 
  CHECK (user_type = ANY(ARRAY['employee', 'company', 'client', 'admin']));

ALTER TABLE public.projects ADD CONSTRAINT projects_status_check 
  CHECK (status = ANY(ARRAY['rfq', 'estimated', 'accepted', 'in_progress', 'completed', 'closed', 'archived']));

ALTER TABLE public.project_tasks ADD CONSTRAINT project_tasks_status_check 
  CHECK (status = ANY(ARRAY['booked', 'in_progress', 'completed', 'cancelled']));

