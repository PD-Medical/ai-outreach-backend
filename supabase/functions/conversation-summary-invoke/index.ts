/**
 * Conversation Summary Invoke Edge Function
 *
 * Train C.1. Generates or returns a cached AI conversation summary for a
 * single thread. Called from the UI on first conversation view (mailbox
 * detail panel + ContactDetailModal Conversations tab) when summary is
 * missing. The Lambda handles the staleness check (compares
 * email_count_at_last_summary against current email_count) so this edge
 * function is a thin proxy.
 *
 * Request body: { conversation_id: string, force?: boolean }
 *
 * Response shape (mirrors summarize_conversation_on_demand return):
 *   {
 *     success: boolean,
 *     cached: boolean,             // true if returned without an LLM call
 *     summary: string | null,
 *     action_items: string[],
 *     last_summarized_at: string | null,
 *     error?: string,
 *   }
 *
 * Auth: requires logged-in user (any role). The Lambda writes to
 * public.conversations via service-role REST API key, not the user's JWT —
 * same pattern as contact-engagement-summary-invoke and email-agent-invoke.
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

interface InvokeRequest {
  conversation_id: string;
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

    if (!body.conversation_id || typeof body.conversation_id !== "string") {
      return new Response(
        JSON.stringify({ success: false, error: "conversation_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Reuse the existing email-sync Lambda Function URL (same lambda hosts
    // the summarize_conversation mode in lambda_email_sync.py).
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
          error: "conversation summary service not configured",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const lambdaPayload = {
      mode: "summarize_conversation",
      conversation_id: body.conversation_id,
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
    console.error("conversation-summary-invoke failed:", err);
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : String(err),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
