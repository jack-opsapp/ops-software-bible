
-- ============================================
-- OPS Courses Schema
-- ============================================

-- Custom types
CREATE TYPE course_status AS ENUM ('draft', 'published', 'archived');
CREATE TYPE lesson_progress_status AS ENUM ('not_started', 'in_progress', 'completed');
CREATE TYPE enrollment_status AS ENUM ('active', 'completed', 'expired');
CREATE TYPE content_block_type AS ENUM ('video', 'text', 'download', 'quiz', 'action_item', 'image', 'embed');
CREATE TYPE quiz_question_type AS ENUM ('multiple_choice', 'scenario', 'true_false');

-- ============================================
-- COURSES
-- ============================================
CREATE TABLE courses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  slug text NOT NULL UNIQUE,
  description text,
  thumbnail_url text,
  price_cents integer NOT NULL DEFAULT 0,
  status course_status NOT NULL DEFAULT 'draft',
  sort_order integer NOT NULL DEFAULT 0,
  estimated_duration_minutes integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_courses_status ON courses(status);
CREATE INDEX idx_courses_slug ON courses(slug);
CREATE INDEX idx_courses_sort_order ON courses(sort_order);

-- ============================================
-- MODULES
-- ============================================
CREATE TABLE modules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_modules_course_id ON modules(course_id);
CREATE INDEX idx_modules_sort_order ON modules(course_id, sort_order);

-- ============================================
-- LESSONS
-- ============================================
CREATE TABLE lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  module_id uuid NOT NULL REFERENCES modules(id) ON DELETE CASCADE,
  title text NOT NULL,
  slug text NOT NULL,
  description text,
  duration_minutes integer,
  sort_order integer NOT NULL DEFAULT 0,
  is_preview boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_lessons_module_id ON lessons(module_id);
CREATE INDEX idx_lessons_sort_order ON lessons(module_id, sort_order);
CREATE UNIQUE INDEX idx_lessons_slug_per_module ON lessons(module_id, slug);

-- ============================================
-- CONTENT BLOCKS
-- ============================================
CREATE TABLE content_blocks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  type content_block_type NOT NULL,
  content jsonb NOT NULL DEFAULT '{}',
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_content_blocks_lesson_id ON content_blocks(lesson_id);
CREATE INDEX idx_content_blocks_sort_order ON content_blocks(lesson_id, sort_order);

-- ============================================
-- QUIZZES
-- ============================================
CREATE TABLE quizzes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid REFERENCES lessons(id) ON DELETE CASCADE,
  module_id uuid REFERENCES modules(id) ON DELETE CASCADE,
  title text NOT NULL,
  passing_score integer NOT NULL DEFAULT 70,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT quiz_parent_check CHECK (
    (lesson_id IS NOT NULL AND module_id IS NULL) OR
    (lesson_id IS NULL AND module_id IS NOT NULL)
  )
);

CREATE INDEX idx_quizzes_lesson_id ON quizzes(lesson_id);
CREATE INDEX idx_quizzes_module_id ON quizzes(module_id);

-- ============================================
-- QUIZ QUESTIONS
-- ============================================
CREATE TABLE quiz_questions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quiz_id uuid NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
  question_text text NOT NULL,
  question_type quiz_question_type NOT NULL DEFAULT 'multiple_choice',
  options jsonb NOT NULL DEFAULT '[]',
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_quiz_questions_quiz_id ON quiz_questions(quiz_id);

-- ============================================
-- ENROLLMENTS
-- ============================================
CREATE TABLE enrollments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  course_id uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  enrolled_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  status enrollment_status NOT NULL DEFAULT 'active',
  UNIQUE(user_id, course_id)
);

CREATE INDEX idx_enrollments_user_id ON enrollments(user_id);
CREATE INDEX idx_enrollments_course_id ON enrollments(course_id);
CREATE INDEX idx_enrollments_status ON enrollments(status);

-- ============================================
-- LESSON PROGRESS
-- ============================================
CREATE TABLE lesson_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  lesson_id uuid NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  status lesson_progress_status NOT NULL DEFAULT 'not_started',
  started_at timestamptz,
  completed_at timestamptz,
  last_position_seconds integer NOT NULL DEFAULT 0,
  UNIQUE(user_id, lesson_id)
);

CREATE INDEX idx_lesson_progress_user_id ON lesson_progress(user_id);
CREATE INDEX idx_lesson_progress_lesson_id ON lesson_progress(lesson_id);

-- ============================================
-- QUIZ ATTEMPTS
-- ============================================
CREATE TABLE quiz_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  quiz_id uuid NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
  score integer NOT NULL,
  passed boolean NOT NULL,
  answers jsonb NOT NULL DEFAULT '[]',
  attempted_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_quiz_attempts_user_id ON quiz_attempts(user_id);
CREATE INDEX idx_quiz_attempts_quiz_id ON quiz_attempts(quiz_id);

-- ============================================
-- CERTIFICATES
-- ============================================
CREATE TABLE certificates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  course_id uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  issued_at timestamptz NOT NULL DEFAULT now(),
  certificate_url text,
  UNIQUE(user_id, course_id)
);

CREATE INDEX idx_certificates_user_id ON certificates(user_id);

-- ============================================
-- STREAKS
-- ============================================
CREATE TABLE streaks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  current_streak integer NOT NULL DEFAULT 0,
  longest_streak integer NOT NULL DEFAULT 0,
  last_activity_date date,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================
-- UPDATED_AT TRIGGER
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER courses_updated_at
  BEFORE UPDATE ON courses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER streaks_updated_at
  BEFORE UPDATE ON streaks
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================

-- Courses: anyone can read published, only admins can write
ALTER TABLE courses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Published courses are viewable by everyone"
  ON courses FOR SELECT
  USING (status = 'published');

-- Modules: readable if parent course is published
ALTER TABLE modules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Modules viewable when course is published"
  ON modules FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM courses
      WHERE courses.id = modules.course_id
      AND courses.status = 'published'
    )
  );

-- Lessons: readable if parent course is published
ALTER TABLE lessons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Lessons viewable when course is published"
  ON lessons FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM modules
      JOIN courses ON courses.id = modules.course_id
      WHERE modules.id = lessons.module_id
      AND courses.status = 'published'
    )
  );

-- Content blocks: readable if parent course is published
ALTER TABLE content_blocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Content blocks viewable when course is published"
  ON content_blocks FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM lessons
      JOIN modules ON modules.id = lessons.module_id
      JOIN courses ON courses.id = modules.course_id
      WHERE lessons.id = content_blocks.lesson_id
      AND courses.status = 'published'
    )
  );

-- Quizzes: readable if parent course is published
ALTER TABLE quizzes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Quizzes viewable when course is published"
  ON quizzes FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM lessons
      JOIN modules ON modules.id = lessons.module_id
      JOIN courses ON courses.id = modules.course_id
      WHERE lessons.id = quizzes.lesson_id
      AND courses.status = 'published'
    )
    OR
    EXISTS (
      SELECT 1 FROM modules
      JOIN courses ON courses.id = modules.course_id
      WHERE modules.id = quizzes.module_id
      AND courses.status = 'published'
    )
  );

-- Quiz questions: same as quizzes
ALTER TABLE quiz_questions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Quiz questions viewable when quiz is viewable"
  ON quiz_questions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM quizzes WHERE quizzes.id = quiz_questions.quiz_id
    )
  );

-- Enrollments: users can see/manage their own
ALTER TABLE enrollments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own enrollments"
  ON enrollments FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "Users can enroll themselves"
  ON enrollments FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Lesson progress: users can see/manage their own
ALTER TABLE lesson_progress ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own progress"
  ON lesson_progress FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "Users can update own progress"
  ON lesson_progress FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can modify own progress"
  ON lesson_progress FOR UPDATE
  USING (auth.uid() = user_id);

-- Quiz attempts: users can see/create their own
ALTER TABLE quiz_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own quiz attempts"
  ON quiz_attempts FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "Users can create own quiz attempts"
  ON quiz_attempts FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Certificates: users can see their own
ALTER TABLE certificates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own certificates"
  ON certificates FOR SELECT
  USING (auth.uid() = user_id);

-- Streaks: users can see/manage their own
ALTER TABLE streaks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own streak"
  ON streaks FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY "Users can create own streak"
  ON streaks FOR INSERT
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own streak"
  ON streaks FOR UPDATE
  USING (auth.uid() = user_id);

