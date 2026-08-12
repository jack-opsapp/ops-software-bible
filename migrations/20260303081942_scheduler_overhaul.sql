-- 1. Add dependencies JSONB to task_types
ALTER TABLE task_types ADD COLUMN IF NOT EXISTS dependencies jsonb DEFAULT '[]'::jsonb;

-- 2. Add dependency overrides JSONB to project_tasks
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS dependency_overrides jsonb;

-- 3. Add time fields to project_tasks (always populated, default 8am/5pm)
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS start_time time DEFAULT '08:00:00';
ALTER TABLE project_tasks ADD COLUMN IF NOT EXISTS end_time time DEFAULT '17:00:00';

-- 4. Add scheduling settings to companies
ALTER TABLE companies ADD COLUMN IF NOT EXISTS precise_scheduling_enabled boolean DEFAULT false;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS skip_weekends_in_auto_schedule boolean DEFAULT true;

-- 5. Index for dependency lookups
CREATE INDEX IF NOT EXISTS idx_task_types_dependencies
  ON task_types USING gin(dependencies);
