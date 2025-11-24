/**
 * Get Tools Edge Function
 *
 * Fetches tool schemas from Lambda for workflow UI consumption
 * This allows the frontend to dynamically discover available tools
 *
 * Deploy: supabase functions deploy get-tools
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// Lambda Function URL (set via environment variable)
// For local dev, use host.docker.internal to reach host machine from Docker
const LAMBDA_FUNCTION_URL = Deno.env.get("GET_TOOL_SCHEMAS_LAMBDA_URL") ||
  "http://host.docker.internal:3001/get-tool-schemas";

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  // Only allow GET requests
  if (req.method !== "GET") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      {
        status: 405,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }

  try {
    if (!LAMBDA_FUNCTION_URL) {
      throw new Error("GET_TOOL_SCHEMAS_LAMBDA_URL environment variable not set");
    }

    console.log("[GetTools] Fetching tool schemas from Lambda...");

    // Call Lambda function
    const lambdaResponse = await fetch(LAMBDA_FUNCTION_URL, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
      },
    });

    if (!lambdaResponse.ok) {
      const errorText = await lambdaResponse.text();
      throw new Error(`Lambda invocation failed: ${lambdaResponse.status} - ${errorText}`);
    }

    const lambdaData = await lambdaResponse.json();

    // Lambda returns { statusCode, body }
    // Parse the body if it's a string
    const toolData = typeof lambdaData.body === "string"
      ? JSON.parse(lambdaData.body)
      : lambdaData.body;

    console.log(`[GetTools] Successfully fetched ${Object.keys(toolData.tools || {}).length} tools`);

    // Return tool schemas
    return new Response(
      JSON.stringify({
        success: true,
        data: toolData.tools,
      }),
      {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );

  } catch (error) {
    console.error("[GetTools] Error:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
});
