
-- Add email-optimized content and LinkedIn article columns for newsletter distribution
ALTER TABLE blog_posts 
  ADD COLUMN IF NOT EXISTS email_content text,
  ADD COLUMN IF NOT EXISTS linkedin_article text,
  ADD COLUMN IF NOT EXISTS image_prompt text;

-- Add comment for documentation
COMMENT ON COLUMN blog_posts.email_content IS 'HTML-formatted email version of the blog post (400-600 words, mobile-friendly)';
COMMENT ON COLUMN blog_posts.linkedin_article IS 'Condensed LinkedIn article version of the blog post';
COMMENT ON COLUMN blog_posts.image_prompt IS 'AI image generation prompt used for the blog thumbnail';

