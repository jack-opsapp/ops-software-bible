-- Step 1: Add scheduling columns to project_tasks
ALTER TABLE project_tasks
  ADD COLUMN start_date timestamptz,
  ADD COLUMN end_date timestamptz,
  ADD COLUMN duration integer;

-- Step 2: Migrate existing calendar_event data into their linked tasks
UPDATE project_tasks pt
SET
  start_date = ce.start_date,
  end_date = ce.end_date,
  duration = ce.duration
FROM calendar_events ce
WHERE pt.calendar_event_id = ce.id;

-- Step 3: Drop the FK column (no longer needed)
ALTER TABLE project_tasks DROP COLUMN calendar_event_id;

-- Step 4: Remove related join tables and references
DROP TABLE IF EXISTS event_team_members CASCADE;

-- Step 5: Drop the calendar_events table
DROP TABLE calendar_events CASCADE;
