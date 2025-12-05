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
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get Lambda URL from system_config
    const { data: configData, error: configError } = await supabase
      .from('system_config')
      .select('value')
      .eq('key', 'get_tool_schemas_url')
      .single();

    const lambdaFunctionUrl = configData?.value;
    if (configError || !lambdaFunctionUrl) {
      console.error("get_tool_schemas_url not found in system_config:", configError);
      throw new Error("Get tool schemas service not configured");
    }

    console.log("[GetTools] Fetching tool schemas from Lambda...");

    // Call Lambda function
    const lambdaResponse = await fetch(lambdaFunctionUrl, {
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
