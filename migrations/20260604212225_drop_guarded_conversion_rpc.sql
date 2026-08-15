-- Drop the superseded guarded conversion RPC (replaced by convert_opportunity_to_project).
-- Verified read-only: 0 code callers, 0 in-DB dependents. Unified path proven in prod.
DROP FUNCTION IF EXISTS public.execute_opportunity_project_conversion_guarded(uuid, uuid, uuid, text, uuid, jsonb);
