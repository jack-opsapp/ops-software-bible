ALTER TABLE courses
  ADD COLUMN display_enrollments integer DEFAULT 0,
  ADD COLUMN display_rating numeric(2,1) DEFAULT 0,
  ADD COLUMN display_review_count integer DEFAULT 0;
