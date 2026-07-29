// ARCHIVED 2026-07-29 (SYSTEMS REPAIR W1-1, bug ba6a5b79). Last deployed source of the
// `delete-user` edge function (v9) before it was tombstoned. See README.md in this directory.
// SECURITY DEFECT (why it died): any valid Supabase-auth session could delete any user.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { supabaseAdmin } from "../_shared/supabase-client.ts";
import { corsHeaders } from "../_shared/cors.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization")!;
    const token = authHeader.replace("Bearer ", "");
    const { data: { user: authUser } } = await supabaseAdmin.auth.getUser(token);
    if (!authUser) throw new Error("Unauthorized");

    const { userId } = await req.json();

    // Get user details
    const { data: user } = await supabaseAdmin.from("users")
      .select("id, auth_id, company_id").eq("id", userId).single();
    if (!user) throw new Error("User not found");

    // Remove from company arrays if in a company
    if (user.company_id) {
      const { data: company } = await supabaseAdmin.from("companies")
        .select("admin_ids, seated_employee_ids").eq("id", user.company_id).single();

      if (company) {
        await supabaseAdmin.from("companies").update({
          admin_ids: (company.admin_ids || []).filter((id: string) => id !== userId),
          seated_employee_ids: (company.seated_employee_ids || []).filter((id: string) => id !== userId),
        }).eq("id", user.company_id);
      }
    }

    // Remove from team assignments (tasks, events, projects)
    // The team_member_ids arrays on projects/tasks/events need cleanup
    // This is best-effort — stale IDs in arrays are harmless

    // Soft-delete the user record
    await supabaseAdmin.from("users").update({
      deleted_at: new Date().toISOString(),
      company_id: null,
      is_active: false,
    }).eq("id", userId);

    // Delete the Supabase Auth account
    if (user.auth_id) {
      await supabaseAdmin.auth.admin.deleteUser(user.auth_id);
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
