-- Step 1: Drop the old check constraint
ALTER TABLE project_tasks DROP CONSTRAINT project_tasks_status_check;

-- Step 2: Migrate existing data: booked/in_progress → active
UPDATE project_tasks
SET status = 'active', updated_at = NOW()
WHERE status IN ('booked', 'in_progress');

-- Step 3: Add new check constraint with 3-state system
ALTER TABLE project_tasks ADD CONSTRAINT project_tasks_status_check
  CHECK (status = ANY (ARRAY['active'::text, 'completed'::text, 'cancelled'::text]));
