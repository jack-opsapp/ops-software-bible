-- Drop existing RLS policies (service role will bypass RLS anyway)
DROP POLICY IF EXISTS "Users can enroll themselves" ON enrollments;
DROP POLICY IF EXISTS "Users can view own enrollments" ON enrollments;

-- Drop FK and unique constraints
ALTER TABLE enrollments DROP CONSTRAINT IF EXISTS enrollments_user_id_fkey;
ALTER TABLE enrollments DROP CONSTRAINT IF EXISTS enrollments_user_id_course_id_key;

-- Change user_id from uuid to text (for Firebase UIDs)
ALTER TABLE enrollments ALTER COLUMN user_id TYPE text USING user_id::text;

-- Re-add unique constraint
ALTER TABLE enrollments ADD CONSTRAINT enrollments_user_id_course_id_key UNIQUE (user_id, course_id);
