// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

const AWS_ACCESS_KEY_ID = Deno.env.get("AWS_EVENTBRIDGE_ACCESS_KEY_ID") ?? "";
const AWS_SECRET_ACCESS_KEY = Deno.env.get("AWS_EVENTBRIDGE_SECRET_ACCESS_KEY") ?? "";
const AWS_REGION = Deno.env.get("AWS_EVENTBRIDGE_REGION") ?? "ap-southeast-2";

// AWS Signature V4 helpers
async function hmacSha256(key: ArrayBuffer, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  return crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message));
}

async function sha256(message: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(message));
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, "0")).join("");
}

async function getSignatureKey(key: string, dateStamp: string, region: string, service: string): Promise<ArrayBuffer> {
  let kDate = await hmacSha256(new TextEncoder().encode("AWS4" + key).buffer, dateStamp);
  let kRegion = await hmacSha256(kDate, region);
  let kService = await hmacSha256(kRegion, service);
  return hmacSha256(kService, "aws4_request");
}

async function signedRequest(
  method: string,
  host: string,
  target: string,
  payload: string
): Promise<Response> {
  const service = "events";
  const now = new Date();
  const amzDate = now.toISOString().replace(/[:\-]|\.\d{3}/g, "");
  const dateStamp = amzDate.slice(0, 8);

  const canonicalHeaders = `content-type:application/x-amz-json-1.1\nhost:${host}\nx-amz-date:${amzDate}\nx-amz-target:${target}\n`;
  const signedHeaders = "content-type;host;x-amz-date;x-amz-target";
  const payloadHash = await sha256(payload);

  const canonicalRequest = `POST\n/\n\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;
  const credentialScope = `${dateStamp}/${AWS_REGION}/${service}/aws4_request`;
  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${credentialScope}\n${await sha256(canonicalRequest)}`;

  const signingKey = await getSignatureKey(AWS_SECRET_ACCESS_KEY, dateStamp, AWS_REGION, service);
  const signatureBytes = await hmacSha256(signingKey, stringToSign);
  const signature = Array.from(new Uint8Array(signatureBytes)).map(b => b.toString(16).padStart(2, "0")).join("");

  const authorization = `AWS4-HMAC-SHA256 Credential=${AWS_ACCESS_KEY_ID}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

  return fetch(`https://${host}/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-amz-json-1.1",
      "X-Amz-Date": amzDate,
      "X-Amz-Target": target,
      "Authorization": authorization,
    },
    body: payload,
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Auth check
  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;

  if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY) {
    return new Response(
      JSON.stringify({ success: false, error: "AWS EventBridge credentials not configured" }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }

  try {
    const body = await req.json();
    const { action, rule_name, schedule_expression } = body;

    if (!action || !rule_name) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing required fields: action, rule_name" }),
        { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    if (!rule_name.startsWith("ai-outreach-")) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid rule_name: must start with 'ai-outreach-'" }),
        { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    const host = `events.${AWS_REGION}.amazonaws.com`;
    let result: Response;

    switch (action) {
      case "enable": {
        result = await signedRequest("POST", host, "AWSEvents.EnableRule",
          JSON.stringify({ Name: rule_name }));
        break;
      }
      case "disable": {
        result = await signedRequest("POST", host, "AWSEvents.DisableRule",
          JSON.stringify({ Name: rule_name }));
        break;
      }
      case "update_schedule": {
        if (!schedule_expression) {
          return new Response(
            JSON.stringify({ success: false, error: "schedule_expression required for update_schedule" }),
            { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
          );
        }
        result = await signedRequest("POST", host, "AWSEvents.PutRule",
          JSON.stringify({
            Name: rule_name,
            ScheduleExpression: schedule_expression,
          }));
        break;
      }
      case "describe": {
        result = await signedRequest("POST", host, "AWSEvents.DescribeRule",
          JSON.stringify({ Name: rule_name }));
        break;
      }
      default:
        return new Response(
          JSON.stringify({ success: false, error: `Unknown action: ${action}. Valid: enable, disable, update_schedule, describe` }),
          { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
        );
    }

    const responseText = await result.text();
    const responseData = responseText ? JSON.parse(responseText) : {};

    if (!result.ok) {
      console.error(`EventBridge ${action} failed:`, responseText);
      return new Response(
        JSON.stringify({ success: false, error: `AWS EventBridge error: ${responseText}` }),
        { status: result.status, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    console.log(`EventBridge ${action} succeeded for ${rule_name}:`, responseData);

    return new Response(
      JSON.stringify({ success: true, action, rule_name, data: responseData }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } }
    );

  } catch (err) {
    console.error("eventbridge-control error:", err);
    return new Response(
      JSON.stringify({ success: false, error: err instanceof Error ? err.message : "Unexpected error" }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }
});
