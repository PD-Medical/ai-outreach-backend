// @ts-nocheck
/**
 * POST /apply-sync-concurrency
 * Body: { max_concurrent: number }
 *
 * 1. Updates system_config['email_sync.max_concurrent_lambdas']
 * 2. Calls Lambda UpdateEventSourceMapping to apply ScalingConfig.MaximumConcurrency
 *    on the email-import-sync function's SQS event source mapping.
 *
 * Auth: requires user with admin role (uses Authorization header from request).
 * IAM: the AWS keys in Supabase secrets must have the policy documented in the
 * /ai-outreach/<env>/edge-function-required-policy SSM parameter (Phase 2 Task 2.4).
 *
 * Uses manual AWS SigV4 (matches the codebase pattern in cloudwatch-metrics /
 * eventbridge-control); the @aws-sdk/* packages from esm.sh do not type-check
 * cleanly under Deno without node_modules.
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAdmin } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ENVIRONMENT = Deno.env.get("ENVIRONMENT") ?? "development";

const AWS_ACCESS_KEY_ID =
  Deno.env.get("AWS_LAMBDA_ACCESS_KEY_ID") ??
  Deno.env.get("AWS_CLOUDWATCH_ACCESS_KEY_ID") ??
  Deno.env.get("AWS_EVENTBRIDGE_ACCESS_KEY_ID") ??
  Deno.env.get("AWS_ACCESS_KEY_ID") ??
  "";
const AWS_SECRET_ACCESS_KEY =
  Deno.env.get("AWS_LAMBDA_SECRET_ACCESS_KEY") ??
  Deno.env.get("AWS_CLOUDWATCH_SECRET_ACCESS_KEY") ??
  Deno.env.get("AWS_EVENTBRIDGE_SECRET_ACCESS_KEY") ??
  Deno.env.get("AWS_SECRET_ACCESS_KEY") ??
  "";
const AWS_REGION =
  Deno.env.get("AWS_LAMBDA_REGION") ??
  Deno.env.get("AWS_CLOUDWATCH_REGION") ??
  Deno.env.get("AWS_EVENTBRIDGE_REGION") ??
  Deno.env.get("AWS_REGION") ??
  "ap-southeast-2";

// --- AWS SigV4 helpers ---------------------------------------------------
async function hmacSha256(key: ArrayBuffer, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message));
}

async function sha256Hex(message: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(message));
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function getSignatureKey(
  key: string,
  dateStamp: string,
  region: string,
  service: string,
): Promise<ArrayBuffer> {
  const kDate = await hmacSha256(
    new TextEncoder().encode("AWS4" + key).buffer,
    dateStamp,
  );
  const kRegion = await hmacSha256(kDate, region);
  const kService = await hmacSha256(kRegion, service);
  return hmacSha256(kService, "aws4_request");
}

/**
 * Sign an AWS Lambda REST API request and execute it.
 * Lambda uses REST (not JSON-1.1 RPC), so canonical URI / query string matter.
 */
async function lambdaRequest(
  method: "GET" | "PUT" | "POST",
  canonicalUri: string,
  canonicalQueryString: string,
  body: string,
): Promise<{ status: number; text: string }> {
  const service = "lambda";
  const host = `lambda.${AWS_REGION}.amazonaws.com`;
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:\-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);

  const payloadHash = await sha256Hex(body);

  const canonicalHeaders =
    `content-type:application/json\n` +
    `host:${host}\n` +
    `x-amz-date:${amzDate}\n`;
  const signedHeaders = "content-type;host;x-amz-date";

  const canonicalRequest =
    `${method}\n${canonicalUri}\n${canonicalQueryString}\n` +
    `${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;

  const credentialScope = `${dateStamp}/${AWS_REGION}/${service}/aws4_request`;
  const stringToSign =
    `AWS4-HMAC-SHA256\n${amzDate}\n${credentialScope}\n` +
    `${await sha256Hex(canonicalRequest)}`;

  const signingKey = await getSignatureKey(
    AWS_SECRET_ACCESS_KEY,
    dateStamp,
    AWS_REGION,
    service,
  );
  const signatureBytes = await hmacSha256(signingKey, stringToSign);
  const signature = Array.from(new Uint8Array(signatureBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  const authorization =
    `AWS4-HMAC-SHA256 Credential=${AWS_ACCESS_KEY_ID}/${credentialScope}, ` +
    `SignedHeaders=${signedHeaders}, Signature=${signature}`;

  const url =
    `https://${host}${canonicalUri}` +
    (canonicalQueryString ? `?${canonicalQueryString}` : "");

  const init: RequestInit = {
    method,
    headers: {
      "Content-Type": "application/json",
      "X-Amz-Date": amzDate,
      "Authorization": authorization,
    },
  };
  if (method !== "GET" && body) {
    (init as { body: string }).body = body;
  }

  const resp = await fetch(url, init);
  const text = await resp.text();
  return { status: resp.status, text };
}

// --- handler -------------------------------------------------------------
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // Admin auth — uses profiles.auth_user_id and profiles.role per requireAdmin
  const auth = await requireAdmin(req);
  if (auth instanceof Response) return auth;

  if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY) {
    return new Response(
      JSON.stringify({ success: false, error: "AWS credentials not configured" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  let payload: { max_concurrent?: unknown } = {};
  try {
    payload = await req.json();
  } catch (_e) {
    return new Response(
      JSON.stringify({ success: false, error: "Invalid JSON body" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const requested = parseInt(String(payload.max_concurrent ?? ""), 10);
  if (!Number.isFinite(requested)) {
    return new Response(
      JSON.stringify({ success: false, error: "max_concurrent must be a number" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
  // Clamp to safe range [2, 50]
  const cap = Math.max(2, Math.min(50, requested || 25));

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1. Persist to system_config (single source of truth for the cap)
  const { error: upsertError } = await supabase
    .from("system_config")
    .upsert(
      { key: "email_sync.max_concurrent_lambdas", value: String(cap) },
      { onConflict: "key" },
    );
  if (upsertError) {
    console.error("system_config upsert failed:", upsertError);
    return new Response(
      JSON.stringify({
        success: false,
        error: `system_config upsert failed: ${upsertError.message}`,
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  // 2. Apply to the SQS event source mapping for email-import-sync-<env>
  const fnName = `email-import-sync-${ENVIRONMENT}`;
  try {
    // List mappings for this function
    const listResp = await lambdaRequest(
      "GET",
      "/2015-03-31/event-source-mappings/",
      `FunctionName=${encodeURIComponent(fnName)}`,
      "",
    );
    if (listResp.status >= 300) {
      console.error("Lambda ListEventSourceMappings failed:", listResp.status, listResp.text);
      return new Response(
        JSON.stringify({
          success: false,
          error: `ListEventSourceMappings ${listResp.status}: ${listResp.text}`,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const listData = JSON.parse(listResp.text);
    const mappings: Array<{ UUID?: string; EventSourceArn?: string }> =
      listData.EventSourceMappings ?? [];
    const mapping = mappings.find((m) =>
      m.EventSourceArn?.includes("email-import-batches-")
    );
    if (!mapping?.UUID) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "event source mapping not found",
          function: fnName,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Update the mapping's ScalingConfig.MaximumConcurrency
    const updateBody = JSON.stringify({
      ScalingConfig: { MaximumConcurrency: cap },
    });
    const updateResp = await lambdaRequest(
      "PUT",
      `/2015-03-31/event-source-mappings/${encodeURIComponent(mapping.UUID)}`,
      "",
      updateBody,
    );
    if (updateResp.status >= 300) {
      console.error("Lambda UpdateEventSourceMapping failed:", updateResp.status, updateResp.text);
      return new Response(
        JSON.stringify({
          success: false,
          error: `UpdateEventSourceMapping ${updateResp.status}: ${updateResp.text}`,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
  } catch (err) {
    console.error("apply-sync-concurrency Lambda call failed:", err);
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : String(err),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  return new Response(
    JSON.stringify({
      success: true,
      ok: true,
      max_concurrent: cap,
      function: fnName,
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
});
