
-- Remove old non-functional inline quiz content blocks
DELETE FROM content_blocks WHERE type = 'quiz';

-- Drop old empty tables
DROP TABLE IF EXISTS quiz_attempts;
DROP TABLE IF EXISTS quiz_questions;
DROP TABLE IF EXISTS quizzes;

-- Drop old assignment_submissions (replaced by assessment_submissions)
DROP TABLE IF EXISTS assignment_submissions;

