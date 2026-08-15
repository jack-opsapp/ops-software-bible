
-- Challenge quiz per course (one-to-one with courses)
CREATE TABLE course_challenges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL UNIQUE REFERENCES courses(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  questions jsonb NOT NULL DEFAULT '[]'::jsonb,
  passing_score integer NOT NULL DEFAULT 80,
  discount_tiers jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- One attempt per user per challenge
CREATE TABLE challenge_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id uuid NOT NULL REFERENCES course_challenges(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  answers jsonb NOT NULL,
  score integer,
  feedback jsonb,
  discount_percentage integer,
  discount_code text,
  status text NOT NULL DEFAULT 'submitted',
  converted boolean NOT NULL DEFAULT false,
  converted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  graded_at timestamptz,
  UNIQUE(challenge_id, user_id)
);

-- Indexes for fast lookups
CREATE INDEX idx_challenge_attempts_user ON challenge_attempts(user_id);
CREATE INDEX idx_challenge_attempts_challenge_user ON challenge_attempts(challenge_id, user_id);

