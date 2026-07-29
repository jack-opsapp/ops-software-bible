// ARCHIVED 2026-07-29 (SYSTEMS REPAIR W1-1). Shared module `_shared/supabase-client.ts`
// bundled with delete-user and terminate-employee (identical copy in both bundles).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Admin client (bypasses RLS) — use for operations that need cross-company access
export const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// Create a client that respects RLS for the current user
export function createUserClient(authHeader: string) {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  );
}
