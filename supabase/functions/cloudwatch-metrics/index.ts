// @ts-nocheck
// Supabase Edge Function - CloudWatch Metrics Proxy
// Returns Lambda function metrics from AWS CloudWatch
// Deploy: supabase functions deploy cloudwatch-metrics

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

const AWS_ACCESS_KEY_ID = Deno.env.get("AWS_CLOUDWATCH_ACCESS_KEY_ID") ?? Deno.env.get("AWS_EVENTBRIDGE_ACCESS_KEY_ID") ?? "";
const AWS_SECRET_ACCESS_KEY = Deno.env.get("AWS_CLOUDWATCH_SECRET_ACCESS_KEY") ?? Deno.env.get("AWS_EVENTBRIDGE_SECRET_ACCESS_KEY") ?? "";
const AWS_REGION = Deno.env.get("AWS_CLOUDWATCH_REGION") ?? Deno.env.get("AWS_EVENTBRIDGE_REGION") ?? "ap-southeast-2";

// Lambda functions to monitor (without environment suffix)
const LAMBDA_FUNCTIONS = [
  "email-import-sync",
  "workflow-matcher",
  "workflow-executor",
  "campaign-executor",
  "campaign-scheduler",
  "email-agent",
  "campaign-sql-agent",
  "get-tool-schemas",
];

// AWS Signature V4 helpers (reused from eventbridge-control)
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
  const kDate = await hmacSha256(new TextEncoder().encode("AWS4" + key).buffer, dateStamp);
  const kRegion = await hmacSha256(kDate, region);
  const kService = await hmacSha256(kRegion, service);
  return hmacSha256(kService, "aws4_request");
}

// Period config: maps user-friendly names to CloudWatch parameters
const PERIOD_CONFIG: Record<string, { seconds: number; step: number }> = {
  "1h":  { seconds: 3600,     step: 60 },      // 1-minute granularity
  "6h":  { seconds: 21600,    step: 300 },     // 5-minute granularity
  "24h": { seconds: 86400,    step: 900 },     // 15-minute granularity
  "7d":  { seconds: 604800,   step: 3600 },    // 1-hour granularity
};

function buildGetMetricDataPayload(environment: string, periodKey: string) {
  const config = PERIOD_CONFIG[periodKey] || PERIOD_CONFIG["24h"];
  const endTime = new Date();
  const startTime = new Date(endTime.getTime() - config.seconds * 1000);

  const metricQueries: any[] = [];
  let queryId = 0;

  for (const fn of LAMBDA_FUNCTIONS) {
    const functionName = `${fn}-${environment}`;
    const prefix = fn.replace(/-/g, "_");

    // Invocations
    metricQueries.push({
      Id: `${prefix}_invocations_${queryId++}`,
      MetricStat: {
        Metric: {
          Namespace: "AWS/Lambda",
          MetricName: "Invocations",
          Dimensions: [{ Name: "FunctionName", Value: functionName }],
        },
        Period: config.step,
        Stat: "Sum",
      },
    });

    // Errors
    metricQueries.push({
      Id: `${prefix}_errors_${queryId++}`,
      MetricStat: {
        Metric: {
          Namespace: "AWS/Lambda",
          MetricName: "Errors",
          Dimensions: [{ Name: "FunctionName", Value: functionName }],
        },
        Period: config.step,
        Stat: "Sum",
      },
    });

    // Duration (avg)
    metricQueries.push({
      Id: `${prefix}_duration_${queryId++}`,
      MetricStat: {
        Metric: {
          Namespace: "AWS/Lambda",
          MetricName: "Duration",
          Dimensions: [{ Name: "FunctionName", Value: functionName }],
        },
        Period: config.step,
        Stat: "Average",
      },
    });

    // Throttles
    metricQueries.push({
      Id: `${prefix}_throttles_${queryId++}`,
      MetricStat: {
        Metric: {
          Namespace: "AWS/Lambda",
          MetricName: "Throttles",
          Dimensions: [{ Name: "FunctionName", Value: functionName }],
        },
        Period: config.step,
        Stat: "Sum",
      },
    });
  }

  return {
    MetricDataQueries: metricQueries,
    StartTime: Math.floor(startTime.getTime() / 1000),
    EndTime: Math.floor(endTime.getTime() / 1000),
  };
}

function parseMetricDataResults(results: any[], environment: string) {
  const functionMap: Record<string, any> = {};

  // Initialize
  for (const fn of LAMBDA_FUNCTIONS) {
    functionMap[fn] = {
      name: fn,
      functionName: `${fn}-${environment}`,
      invocations: 0,
      errors: 0,
      avgDuration: 0,
      throttles: 0,
      datapoints: [],
    };
  }

  // Parse results
  for (const result of results) {
    const id = result.Id || "";
    // Find which function and metric this belongs to
    for (const fn of LAMBDA_FUNCTIONS) {
      const prefix = fn.replace(/-/g, "_");
      if (id.startsWith(prefix + "_")) {
        const metricPart = id.replace(prefix + "_", "").replace(/_\d+$/, "");
        const values = result.Values || [];
        const timestamps = result.Timestamps || [];

        if (metricPart === "invocations") {
          functionMap[fn].invocations = values.reduce((a: number, b: number) => a + b, 0);
          // Build datapoints from invocations timestamps
          for (let i = 0; i < timestamps.length; i++) {
            const existing = functionMap[fn].datapoints.find((d: any) => d.timestamp === timestamps[i]);
            if (existing) {
              existing.invocations = values[i];
            } else {
              functionMap[fn].datapoints.push({ timestamp: timestamps[i], invocations: values[i], errors: 0 });
            }
          }
        } else if (metricPart === "errors") {
          functionMap[fn].errors = values.reduce((a: number, b: number) => a + b, 0);
          for (let i = 0; i < timestamps.length; i++) {
            const existing = functionMap[fn].datapoints.find((d: any) => d.timestamp === timestamps[i]);
            if (existing) {
              existing.errors = values[i];
            } else {
              functionMap[fn].datapoints.push({ timestamp: timestamps[i], invocations: 0, errors: values[i] });
            }
          }
        } else if (metricPart === "duration") {
          functionMap[fn].avgDuration = values.length > 0
            ? Math.round(values.reduce((a: number, b: number) => a + b, 0) / values.length)
            : 0;
        } else if (metricPart === "throttles") {
          functionMap[fn].throttles = values.reduce((a: number, b: number) => a + b, 0);
        }
        break;
      }
    }
  }

  // Sort datapoints by timestamp
  for (const fn of LAMBDA_FUNCTIONS) {
    functionMap[fn].datapoints.sort((a: any, b: any) =>
      new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
    );
  }

  return Object.values(functionMap);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;

  if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY) {
    return new Response(
      JSON.stringify({ success: false, error: "AWS CloudWatch credentials not configured" }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }

  const VALID_ENVIRONMENTS = ["production", "staging", "dev"];

  try {
    const body = await req.json();
    const period = body.period || "24h";
    const environment = body.environment || "production";

    if (!PERIOD_CONFIG[period]) {
      return new Response(
        JSON.stringify({ success: false, error: `Invalid period: ${period}. Valid: 1h, 6h, 24h, 7d` }),
        { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    if (!VALID_ENVIRONMENTS.includes(environment)) {
      return new Response(
        JSON.stringify({ success: false, error: `Invalid environment: ${environment}. Valid: ${VALID_ENVIRONMENTS.join(", ")}` }),
        { status: 400, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    // Build and send GetMetricData request
    const payload = buildGetMetricDataPayload(environment, period);
    const cwPayload = JSON.stringify(payload);

    // CloudWatch GetMetricData uses a specific action header
    const host = `monitoring.${AWS_REGION}.amazonaws.com`;
    const now = new Date();
    const amzDate = now.toISOString().replace(/[:\-]|\.\d{3}/g, "");
    const dateStamp = amzDate.slice(0, 8);

    const canonicalHeaders = `content-type:application/json\nhost:${host}\nx-amz-date:${amzDate}\n`;
    const signedHeaders = "content-type;host;x-amz-date";
    const payloadHash = await sha256(cwPayload);

    const canonicalRequest = `POST\n/\n\n${canonicalHeaders}\n${signedHeaders}\n${payloadHash}`;
    const credentialScope = `${dateStamp}/${AWS_REGION}/monitoring/aws4_request`;
    const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${credentialScope}\n${await sha256(canonicalRequest)}`;

    const signingKey = await getSignatureKey(AWS_SECRET_ACCESS_KEY, dateStamp, AWS_REGION, "monitoring");
    const signatureBytes = await hmacSha256(signingKey, stringToSign);
    const signature = Array.from(new Uint8Array(signatureBytes)).map(b => b.toString(16).padStart(2, "0")).join("");

    const authorization = `AWS4-HMAC-SHA256 Credential=${AWS_ACCESS_KEY_ID}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;

    const cwResponse = await fetch(`https://${host}/`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Amz-Date": amzDate,
        "Authorization": authorization,
        "X-Amz-Target": "GraniteServiceVersion20100801.GetMetricData",
      },
      body: cwPayload,
    });

    const responseText = await cwResponse.text();

    if (!cwResponse.ok) {
      console.error("CloudWatch API error:", responseText);
      return new Response(
        JSON.stringify({ success: false, error: `CloudWatch API error: ${cwResponse.status}` }),
        { status: cwResponse.status, headers: { "Content-Type": "application/json", ...corsHeaders } }
      );
    }

    const cwData = JSON.parse(responseText);
    const functions = parseMetricDataResults(cwData.MetricDataResults || [], environment);

    // Compute totals
    const totals = {
      invocations: functions.reduce((s: number, f: any) => s + f.invocations, 0),
      errors: functions.reduce((s: number, f: any) => s + f.errors, 0),
      avgDuration: (() => {
        const withDuration = functions.filter((f: any) => f.avgDuration > 0);
        return withDuration.length > 0
          ? Math.round(withDuration.reduce((s: number, f: any) => s + f.avgDuration, 0) / withDuration.length)
          : 0;
      })(),
      throttles: functions.reduce((s: number, f: any) => s + f.throttles, 0),
    };

    return new Response(
      JSON.stringify({
        success: true,
        period,
        environment,
        totals,
        functions,
        fetchedAt: new Date().toISOString(),
      }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } }
    );

  } catch (err) {
    console.error("cloudwatch-metrics error:", err);
    return new Response(
      JSON.stringify({ success: false, error: err instanceof Error ? err.message : "Unexpected error" }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    );
  }
});
