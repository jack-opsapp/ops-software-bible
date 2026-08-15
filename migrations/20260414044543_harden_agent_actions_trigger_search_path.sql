-- Security hardening: pin search_path on trigger function so the role
-- that owns it cannot be tricked into resolving a malicious schema
-- object at execution time. Matches the pattern recommended by the
-- Supabase security linter.

CREATE OR REPLACE FUNCTION update_agent_actions_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;
