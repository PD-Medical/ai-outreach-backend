/**
 * Conversation Summary Invoke Edge Function (Train C.1, hardened in C.1.1)
 *
 * Generates or returns a cached AI conversation summary for a single thread.
 * Called from the UI on first conversation view (mailbox detail panel +
 * ContactDetailModal Conversations tab) when summary is missing. The Lambda
 * handles staleness; this is an authenticated proxy with rate limiting.
 *
 * Request body: { conversation_id: string, force?: boolean }
 *
 * Response shape (mirrors summarize_conversation_on_demand return):
 *   {
 *     success: boolean,
 *     cached: boolean,
 *     summary: string | null,
 *     action_items: string[],
 *     last_summarized_at: string | null,
 *     error?: string,
 *   }
 *
 * Auth: requireAuth + RLS-filtered conversation existence check.
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
  conversation_id: string;
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

  // Generate a correlation ID up-front so unexpected errors can surface
  // a stable identifier without leaking internal details.
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

    if (!body.conversation_id || !UUID_RE.test(body.conversation_id)) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "conversation_id must be a UUID",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Force regen is privileged — it skips the cache and re-spends LLM budget.
    // Gate behind admin role; everyone else can still get a cached/lazy summary.
    const force = !!body.force;
    const auth = force ? await requireAdmin(req) : await requireAuth(req);
    if (auth instanceof Response) return auth;
    const { user } = auth;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Per-user rate limit. Skip for service-role callers (internal jobs).
    if (!user.is_service_role) {
      const { data: rl, error: rlError } = await supabase.rpc(
        "check_and_increment_rate_limit",
        {
          p_user_id: user.id,
          p_resource: "conversation_summary",
          p_max_per_minute: RATE_LIMIT_PER_MINUTE,
        },
      );
      if (rlError) {
        console.error(`[${correlationId}] rate_limit_rpc_failed`, rlError);
        // Fail open on rate-limit infrastructure failures — better to allow
        // than to block legit traffic.
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

    // Per-resource authorization: confirm the conversation exists and the
    // caller can read it. We use a user-scoped client (anon key + caller's
    // JWT) so RLS filters out unauthorized rows. If the row isn't visible
    // to this user, we 403 — same response as if the conversation didn't
    // exist (don't leak existence of conversations the user can't see).
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
      const { data: convRow, error: convErr } = await userClient
        .from("conversations")
        .select("id")
        .eq("id", body.conversation_id)
        .maybeSingle();
      if (convErr) {
        console.error(`[${correlationId}] conversation_authz_lookup_failed`, convErr);
        return new Response(
          JSON.stringify({
            success: false,
            error: "Authorization check failed",
            correlation_id: correlationId,
          }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      if (!convRow) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Conversation not found or access denied",
          }),
          { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
    }

    // Reuse the existing email-sync Lambda Function URL.
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
          error: "conversation summary service not configured",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    // Validate the URL parse — guards against placeholder values like "TODO".
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
          error: "conversation summary service misconfigured",
        }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const lambdaPayload = {
      mode: "summarize_conversation",
      conversation_id: body.conversation_id,
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

    // Lambda dispatcher wraps responses as { statusCode, body }; unwrap.
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

    // Status mapping after unwrap:
    //   - lambda transport failure (!ok AND no parsable body) -> 502
    //   - lambda returned structured success/failure JSON -> 200 (the body
    //     carries success=true/false; HTTP status reflects transport, not app)
    //   - everything else -> 502
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
    console.error(`[${correlationId}] conversation-summary-invoke failed:`, err);
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
