
-- The company_self_access RLS policy references private.get_user_company_id()
-- but the authenticated role doesn't have USAGE on the private schema,
-- causing policy evaluation to error and block all INSERTs into companies.
GRANT USAGE ON SCHEMA private TO authenticated;

