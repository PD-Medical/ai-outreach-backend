/**
 * Contact Call Plan Invoke Edge Function
 *
 * Authenticated proxy for Lambda mode `contact_call_plan`.
 *
 * Request body: { contact_id: string, instruction?: string, force?: boolean }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

interface InvokeRequest {
  contact_id: string;
  instruction?: string;
  force?: boolean;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RATE_LIMIT_PER_MINUTE = 10;
const LAMBDA_TIMEOUT_MS = 60_000;

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }

  const correlationId = crypto.randomUUID();

  try {
    let body: InvokeRequest;
    try {
      body = await req.json();
    } catch (_e) {
      return jsonResponse({ success: false, error: "Invalid JSON body" }, 400);
    }

    if (!body.contact_id || !UUID_RE.test(body.contact_id)) {
      return jsonResponse({ success: false, error: "contact_id must be a UUID" }, 400);
    }

    const instruction =
      typeof body.instruction === "string" && body.instruction.trim()
        ? body.instruction.trim().slice(0, 1200)
        : null;

    const auth = await requireAuth(req);
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
          p_resource: "contact_call_plan",
          p_max_per_minute: RATE_LIMIT_PER_MINUTE,
        },
      );
      if (rlError) {
        console.error(`[${correlationId}] rate_limit_rpc_failed`, rlError);
      } else if (rl && rl.allowed === false) {
        return jsonResponse(
          {
            success: false,
            error: `Rate limit exceeded: ${rl.count} of ${rl.limit} per minute. Try again shortly.`,
          },
          429,
        );
      }
    }

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
        return jsonResponse(
          {
            success: false,
            error: "Authorization check failed",
            correlation_id: correlationId,
          },
          500,
        );
      }
      if (!contactRow) {
        return jsonResponse(
          { success: false, error: "Contact not found or access denied" },
          403,
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
      return jsonResponse(
        { success: false, error: "call planning service not configured" },
        503,
      );
    }
    try {
      const parsed = new URL(lambdaUrl);
      if (parsed.protocol !== "https:") throw new Error("non-https lambda url");
    } catch (e) {
      console.error(`[${correlationId}] email_sync_url_invalid`, e);
      return jsonResponse(
        { success: false, error: "call planning service misconfigured" },
        503,
      );
    }

    let lambdaResponse: Response;
    try {
      lambdaResponse = await fetch(lambdaUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mode: "contact_call_plan",
          contact_id: body.contact_id,
          instruction,
          force: !!body.force,
        }),
        signal: AbortSignal.timeout(LAMBDA_TIMEOUT_MS),
      });
    } catch (e) {
      const isTimeout = e instanceof DOMException && e.name === "TimeoutError";
      console.error(`[${correlationId}] lambda_fetch_failed`, isTimeout ? "timeout" : e);
      return jsonResponse(
        {
          success: false,
          error: isTimeout
            ? "Call plan generation timed out — please retry"
            : "Call planning service unavailable",
          correlation_id: correlationId,
        },
        isTimeout ? 504 : 502,
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
    return jsonResponse(result, isStructured ? 200 : lambdaResponse.ok ? 200 : 502);
  } catch (err) {
    console.error(`[${correlationId}] contact-call-plan-invoke failed:`, err);
    return jsonResponse(
      {
        success: false,
        error: "Internal error — please retry or contact support",
        correlation_id: correlationId,
      },
      500,
    );
  }
});
