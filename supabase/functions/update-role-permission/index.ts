// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.3";
import { corsHeaders } from "../_shared/cors.ts";

type RoleType = "admin" | "sales" | "accounts" | "management";
type PermissionKey =
  | "view_users"
  | "manage_users"
  | "view_contacts"
  | "manage_contacts"
  | "view_campaigns"
  | "manage_campaigns"
  | "approve_campaigns"
  | "view_analytics"
  | "manage_approvals";

interface RequestBody {
  role?: RoleType;
  permission?: PermissionKey;
  value?: boolean;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  throw new Error("Missing Supabase environment variables");
}

const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

function validate(body: RequestBody) {
  if (!body.role || !body.permission || typeof body.value !== "boolean") {
    return "Missing role, permission, or value";
  }
  return null;
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return new Response(JSON.stringify({ success: false, message: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  try {
    const body = (await request.json()) as RequestBody;
    const validationError = validate(body);

    if (validationError) {
      return new Response(JSON.stringify({ success: false, message: validationError }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const { role, permission, value } = body as Required<RequestBody>;

    const { error } = await supabaseAdmin
      .from("role_permissions")
      .update({ [permission]: value })
      .eq("role", role);

    if (error) {
      console.error("Failed to update role permission", error);
      return new Response(JSON.stringify({ success: false, message: "Database update failed" }), {
        status: 500,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    return new Response(JSON.stringify({ success: true, message: "Permission updated" }), {
      status: 200,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (error) {
    console.error("Unexpected error updating role permission", error);
    return new Response(JSON.stringify({ success: false, message: "Unexpected error" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
