
-- 1. Add 'assignment' to content_block_type enum
ALTER TYPE content_block_type ADD VALUE 'assignment';

-- 2. Create assignment_submissions table
CREATE TABLE assignment_submissions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id text NOT NULL,
  content_block_id uuid NOT NULL REFERENCES content_blocks(id),
  answers jsonb NOT NULL,
  score integer,
  feedback jsonb,
  status text NOT NULL DEFAULT 'submitted',
  created_at timestamptz DEFAULT now(),
  graded_at timestamptz
);

CREATE INDEX idx_submissions_user_block ON assignment_submissions(user_id, content_block_id);

-- 3. RLS policies
ALTER TABLE assignment_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own submissions" ON assignment_submissions
  FOR SELECT USING (true);

CREATE POLICY "Users can insert own submissions" ON assignment_submissions
  FOR INSERT WITH CHECK (true);

