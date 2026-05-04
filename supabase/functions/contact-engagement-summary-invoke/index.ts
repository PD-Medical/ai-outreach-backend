/**
 * Contact Engagement Summary Invoke Edge Function (Train E, hardened in C.1.1)
 *
 * Generates or returns a cached AI engagement summary for a contact. Called
 * from the ContactDetailModal Overview tab on first view; the Lambda handles
 * the staleness check, this is an authenticated proxy with rate limiting.
 *
 * Request body: { contact_id: string, force?: boolean }
 *
 * Response shape (mirrors generate_engagement_summary return):
 *   {
 *     success: boolean,
 *     cached: boolean,
 *     engagement_summary: string | null,
 *     engagement_action_items: string[],
 *     engagement_summary_at: string | null,
 *     error?: string,
 *   }
 *
 * Auth: requireAuth + RLS-filtered contact existence check.
 *       force=true requires requireAdmin (privileged: re-spends LLM budget).
 *       Per-user rate limit: 10 summary requests / minute.
 *
 * Timeout: 60s on the Lambda fetch — surfaces a 504 to the frontend rather
 * than letting Supabase's edge-runtime kill it at ~150s.
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth, requireAdmin } from "../_shared/auth.ts";

interface InvokeRequest {
  contact_id: string;
  force?: boolean;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RATE_LIMIT_PER_MINUTE = 10;
const LAMBDA_TIMEOUT_MS = 60_000;

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

  const correlationId = crypto.randomUUID();

  try {
    let body: InvokeRequest;
    try {
      body = await req.json();
    } catch (_e) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid JSON body" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    if (!body.contact_id || !UUID_RE.test(body.contact_id)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "contact_id must be a UUID",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const force = !!body.force;
    const auth = force ? await requireAdmin(req) : await requireAuth(req);
    if (auth instanceof Response) return auth;
    const { user } = auth;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    if (!user.is_service_role) {
      const { data: rl, error: rlError } = await supabase.rpc(
        "check_and_increment_rate_limit",
        {
          p_user_id: user.id,
          p_resource: "engagement_summary",
          p_max_per_minute: RATE_LIMIT_PER_MINUTE,
        },
      );
      if (rlError) {
        console.error(`[${correlationId}] rate_limit_rpc_failed`, rlError);
        // fail open
      } else if (rl && rl.allowed === false) {
        return new Response(
          JSON.stringify({
            success: false,
            error: `Rate limit exceeded: ${rl.count} of ${rl.limit} per minute. Try again shortly.`,
          }),
          {
            status: 429,
            headers: {
              ...corsHeaders,
              "Content-Type": "application/json",
              "Retry-After": "60",
            },
          },
        );
      }
    }

    // Per-resource authorization via user-scoped client (RLS filters).
    if (!user.is_service_role) {
      const userClient = createClient(
        Deno.env.get("SUPABASE_URL") ?? "",
        Deno.env.get("SUPABASE_ANON_KEY") ?? "",
        {
          global: {
            headers: { Authorization: req.headers.get("authorization") ?? "" },
          },
          auth: { persistSession: false, autoRefreshToken: false },
        },
      );
      const { data: contactRow, error: contactErr } = await userClient
        .from("contacts")
        .select("id")
        .eq("id", body.contact_id)
        .maybeSingle();
      if (contactErr) {
        console.error(`[${correlationId}] contact_authz_lookup_failed`, contactErr);
        return new Response(
          JSON.stringify({
            success: false,
            error: "Authorization check failed",
            correlation_id: correlationId,
          }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      if (!contactRow) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Contact not found or access denied",
          }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    const { data: configData, error: configError } = await supabase
      .from("system_config")
      .select("value")
      .eq("key", "email_sync_url")
      .single();

    const lambdaUrl = configData?.value;
    if (configError || !lambdaUrl || typeof lambdaUrl !== "string") {
      console.error(`[${correlationId}] email_sync_url_missing`, configError);
      return new Response(
        JSON.stringify({
          success: false,
          error: "engagement summary service not configured",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    try {
      const parsed = new URL(lambdaUrl);
      if (parsed.protocol !== "https:") {
        throw new Error("non-https lambda url");
      }
    } catch (e) {
      console.error(`[${correlationId}] email_sync_url_invalid`, e);
      return new Response(
        JSON.stringify({
          success: false,
          error: "engagement summary service misconfigured",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const lambdaPayload = {
      mode: "engagement_summary",
      contact_id: body.contact_id,
      force,
    };

    let lambdaResponse: Response;
    try {
      lambdaResponse = await fetch(lambdaUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(lambdaPayload),
        signal: AbortSignal.timeout(LAMBDA_TIMEOUT_MS),
      });
    } catch (e) {
      const isTimeout =
        e instanceof DOMException && e.name === "TimeoutError";
      console.error(
        `[${correlationId}] lambda_fetch_failed`,
        isTimeout ? "timeout" : e,
      );
      return new Response(
        JSON.stringify({
          success: false,
          error: isTimeout
            ? "Summary generation timed out — please retry"
            : "Summary service unavailable",
          correlation_id: correlationId,
        }),
        {
          status: isTimeout ? 504 : 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const text = await lambdaResponse.text();
    let result: unknown;
    try {
      result = JSON.parse(text);
    } catch {
      result = { success: false, error: text || "lambda returned non-JSON response" };
    }

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

    const isStructured =
      result && typeof result === "object" && "success" in (result as Record<string, unknown>);
    const status = isStructured
      ? 200
      : (lambdaResponse.ok ? 200 : 502);

    return new Response(JSON.stringify(result), {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error(`[${correlationId}] contact-engagement-summary-invoke failed:`, err);
    return new Response(
      JSON.stringify({
        success: false,
        error: "Internal error — please retry or contact support",
        correlation_id: correlationId,
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
