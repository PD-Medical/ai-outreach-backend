import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "./cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/**
 * Validate the user's Bearer token from the Authorization header.
 * Returns { user } on success, or a 401 Response on failure.
 *
 * Usage:
 *   const auth = await requireAuth(req);
 *   if (auth instanceof Response) return auth;
 *   const { user } = auth;
 */
export async function requireAuth(
  req: Request
): Promise<{ user: any } | Response> {
  const authHeader = req.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(
      JSON.stringify({ error: "Missing or invalid authorization header" }),
      { status: 401, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }

  const token = authHeader.replace("Bearer ", "");

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: { user }, error } = await supabase.auth.getUser(token);

  if (error || !user) {
    return new Response(
      JSON.stringify({ error: "Invalid or expired session" }),
      { status: 401, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }

  return { user };
}

/**
 * Validate the user's Bearer token AND verify they have the "admin" role.
 * Returns { user } on success, a 401 Response if not authenticated,
 * or a 403 Response if authenticated but not an admin.
 *
 * Usage:
 *   const auth = await requireAdmin(req);
 *   if (auth instanceof Response) return auth;
 *   const { user } = auth;
 */
export async function requireAdmin(
  req: Request
): Promise<{ user: any } | Response> {
  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;

  const { user } = auth;

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Look up the caller's profile to check their role
  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("role")
    .eq("auth_user_id", user.id)
    .maybeSingle();

  if (profileError || !profile) {
    return new Response(
      JSON.stringify({ error: "Forbidden: unable to verify admin role" }),
      { status: 403, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }

  if (profile.role !== "admin") {
    return new Response(
      JSON.stringify({ error: "Forbidden: admin role required" }),
      { status: 403, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }

  return { user };
}
