// ARCHIVED 2026-07-29 (SYSTEMS REPAIR W1-1, bug ba6a5b79). Last deployed source of the
// `terminate-employee` edge function (v9) before it was tombstoned. See README.md in this
// directory. SECURITY DEFECT (why it died): caller admin-ship was checked against the POSTED
// companyId, but the target user's membership in that company was never checked — an admin
// of company A could strip users in any tenant.
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

    const { userId, companyId } = await req.json();

    // Verify caller is admin
    const { data: company } = await supabaseAdmin.from("companies")
      .select("admin_ids, seated_employee_ids").eq("id", companyId).single();

    const callerUserId = (await supabaseAdmin.from("users")
      .select("id").eq("auth_id", authUser.id).single()).data?.id;

    if (!company?.admin_ids?.includes(callerUserId)) {
      throw new Error("Only admins can terminate employees");
    }

    // Remove from admin_ids if present
    const updatedAdminIds = (company.admin_ids || []).filter((id: string) => id !== userId);
    const updatedSeatedIds = (company.seated_employee_ids || []).filter((id: string) => id !== userId);

    await supabaseAdmin.from("companies").update({
      admin_ids: updatedAdminIds,
      seated_employee_ids: updatedSeatedIds,
    }).eq("id", companyId);

    // Update user: remove company association
    await supabaseAdmin.from("users").update({
      company_id: null,
      role: "Field Crew",
      is_company_admin: false,
      is_active: false,
    }).eq("id", userId);

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
