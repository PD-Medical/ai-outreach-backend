/**
 * Email Sync Trigger Edge Function
 *
 * Proxies email sync requests from frontend to Lambda.
 * Reads Lambda URL from system_config table.
 *
 * Request body:
 * {
 *   mode: 'sync' | 'legacy' | 'retry_errors' | 'retry_missing',
 *   mailbox_ids?: string[],
 *   folders?: string[],
 *   batch_limit?: number
 * }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface SyncRequest {
  mode: 'sync' | 'legacy' | 'retry_errors' | 'retry_missing';
  mailbox_ids?: string[];
  folders?: string[];
  batch_limit?: number;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Validate auth
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse request
    const body: SyncRequest = await req.json();
    console.log(`User ${user.id} (${user.email}) triggering email sync:`, JSON.stringify(body));

    // Get Lambda URL from system_config
    const { data: configData, error: configError } = await supabase
      .from('system_config')
      .select('value')
      .eq('key', 'email_sync_url')
      .single();

    const lambdaUrl = configData?.value;
    if (configError || !lambdaUrl) {
      console.error("email_sync_url not found in system_config:", configError);
      return new Response(
        JSON.stringify({ error: "Email sync service not configured" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Invoking email-sync Lambda: ${lambdaUrl}`);

    // Forward to Lambda
    const lambdaResponse = await fetch(lambdaUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    const lambdaResult = await lambdaResponse.json();
    console.log('Lambda response status:', lambdaResponse.status);

    return new Response(
      JSON.stringify(lambdaResult),
      {
        status: lambdaResponse.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      }
    );

  } catch (error) {
    console.error('Error in email-sync-trigger:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
