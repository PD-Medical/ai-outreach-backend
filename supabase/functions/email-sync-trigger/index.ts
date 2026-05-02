/**
 * Email Sync Trigger Edge Function
 *
 * Proxies email sync requests from frontend to Lambda.
 * Reads Lambda URL from system_config table.
 *
 * Request body:
 * {
 *   mode: 'sync' | 'legacy' | 'retry_errors' | 'retry_missing'
 *       | 'enrich_pending' | 'check_openrouter_status',
 *   mailbox_ids?: string[],
 *   folders?: string[],
 *   batch_limit?: number,
 *   error_ids?: string[],
 *   force?: boolean
 * }
 *
 * The Lambda dispatcher accepts all listed modes (added enrich_pending and
 * check_openrouter_status in the email-sync-job-management feature).
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

interface SyncRequest {
  mode:
    | 'sync'
    | 'legacy'
    | 'retry_errors'
    | 'retry_missing'
    | 'enrich_pending'
    | 'check_openrouter_status';
  mailbox_ids?: string[];
  folders?: string[];
  batch_limit?: number;
  error_ids?: string[];
  force?: boolean;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    // Authenticate user
    const auth = await requireAuth(req);
    if (auth instanceof Response) return auth;
    const { user } = auth;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

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
      JSON.stringify({ error: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
