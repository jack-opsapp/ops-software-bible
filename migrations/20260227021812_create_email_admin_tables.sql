
-- Newsletter content table for composing monthly newsletters
CREATE TABLE IF NOT EXISTS newsletter_content (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  month integer NOT NULL CHECK (month BETWEEN 1 AND 12),
  year integer NOT NULL CHECK (year >= 2024),
  shipped text[] DEFAULT '{}',
  in_progress text[] DEFAULT '{}',
  bug_fixes text[] DEFAULT '{}',
  coming_up text[] DEFAULT '{}',
  custom_intro text,
  custom_outro text,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'sent')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(month, year)
);

-- Enable RLS (admin-only via service role)
ALTER TABLE newsletter_content ENABLE ROW LEVEL SECURITY;

-- Postgres function: segment counts from users table
-- Returns counts of users in each email segment
CREATE OR REPLACE FUNCTION email_segment_counts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total_users', (SELECT count(*) FROM users),
    'bubble_reauth', (SELECT count(*) FROM users WHERE email_domain_valid = false AND removed_from_email_list = false),
    'unverified', (SELECT count(*) FROM users WHERE onboarding_completed = false AND removed_from_email_list = false),
    'auth_lifecycle', (SELECT count(*) FROM users WHERE onboarding_completed = true AND removed_from_email_list = false),
    'removed', (SELECT count(*) FROM users WHERE removed_from_email_list = true)
  ) INTO result;
  RETURN result;
END;
$$;

-- Postgres function: email funnel counts from email_log
-- Returns send counts grouped by email_type
CREATE OR REPLACE FUNCTION email_funnel_counts()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT COALESCE(
    jsonb_object_agg(email_type, cnt),
    '{}'::jsonb
  )
  FROM (
    SELECT email_type, count(*) as cnt
    FROM email_log
    GROUP BY email_type
  ) sub
  INTO result;
  RETURN result;
END;
$$;

