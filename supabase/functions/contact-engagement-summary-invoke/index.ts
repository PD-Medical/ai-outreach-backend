/**
 * Contact Engagement Summary Invoke Edge Function
 *
 * Train E. Generates or returns a cached AI engagement summary for a contact.
 * Called from the ContactDetailModal Overview tab on first view; the Lambda
 * handles the staleness check (compares engagement_conv_count_at_last_summary
 * against current sum of email_count_at_last_summary across the contact's
 * conversations) so this edge function is a thin proxy.
 *
 * Request body: { contact_id: string, force?: boolean }
 *
 * Response shape (mirrors generate_engagement_summary return):
 *   {
 *     success: boolean,
 *     cached: boolean,             // true if returned without an LLM call
 *     engagement_summary: string | null,
 *     engagement_action_items: string[],
 *     engagement_summary_at: string | null,
 *     error?: string,
 *   }
 *
 * Auth: requires logged-in user (any role). The Lambda writes to public.contacts
 * via service-role REST API key, not the user's JWT — same pattern as
 * email-agent-invoke.
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

interface InvokeRequest {
  contact_id: string;
  force?: boolean;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const auth = await requireAuth(req);
    if (auth instanceof Response) return auth;

    let body: InvokeRequest;
    try {
      body = await req.json();
    } catch (_e) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid JSON body" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!body.contact_id || typeof body.contact_id !== "string") {
      return new Response(
        JSON.stringify({ success: false, error: "contact_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Reuse the existing email-sync Lambda Function URL (same lambda hosts the
    // engagement_summary mode in lambda_email_sync.py).
    const { data: configData, error: configError } = await supabase
      .from("system_config")
      .select("value")
      .eq("key", "email_sync_url")
      .single();

    const lambdaUrl = configData?.value;
    if (configError || !lambdaUrl) {
      console.error("email_sync_url not in system_config:", configError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "engagement summary service not configured",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const lambdaPayload = {
      mode: "engagement_summary",
      contact_id: body.contact_id,
      force: !!body.force,
    };

    const lambdaResponse = await fetch(lambdaUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(lambdaPayload),
    });

    const text = await lambdaResponse.text();
    let result: unknown;
    try {
      result = JSON.parse(text);
    } catch {
      // Some lambda responses come back as { statusCode, body } where body
      // is itself a JSON-encoded string. Pass through unparsed text in that case.
      result = { success: false, error: text || "lambda returned non-JSON response" };
    }

    // The lambda dispatcher wraps the response as { statusCode, body }; unwrap if so.
    if (
      result &&
      typeof result === "object" &&
      "body" in (result as Record<string, unknown>) &&
      typeof (result as Record<string, unknown>).body === "string"
    ) {
      try {
        result = JSON.parse((result as Record<string, string>).body);
      } catch {
        // leave as-is
      }
    }

    return new Response(JSON.stringify(result), {
      status: lambdaResponse.ok ? 200 : 502,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("contact-engagement-summary-invoke failed:", err);
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : String(err),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
