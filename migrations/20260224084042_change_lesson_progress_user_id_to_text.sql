
-- Drop ALL RLS policies on lesson_progress
DROP POLICY IF EXISTS "Users can modify own progress" ON lesson_progress;
DROP POLICY IF EXISTS "Users can update own progress" ON lesson_progress;
DROP POLICY IF EXISTS "Users can view own progress" ON lesson_progress;

-- Disable RLS
ALTER TABLE lesson_progress DISABLE ROW LEVEL SECURITY;

-- Drop FK to auth.users
ALTER TABLE lesson_progress DROP CONSTRAINT IF EXISTS lesson_progress_user_id_fkey;

-- Change user_id from uuid to text for Firebase UIDs
ALTER TABLE lesson_progress ALTER COLUMN user_id TYPE text USING user_id::text;

