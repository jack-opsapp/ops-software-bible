
-- Remove the triggers created by previous agent
DROP TRIGGER IF EXISTS on_onboarding_complete ON users;
DROP TRIGGER IF EXISTS on_first_project ON projects;
DROP TRIGGER IF EXISTS on_first_client ON clients;

-- Remove the trigger functions
DROP FUNCTION IF EXISTS notify_onboarding_complete();
DROP FUNCTION IF EXISTS notify_first_action();
DROP FUNCTION IF EXISTS http_post_to_edge_function(text, jsonb);

