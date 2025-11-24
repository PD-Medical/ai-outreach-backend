/**
 * Email Agent Resume Edge Function
 *
 * Handles user decisions on pending email drafts (approve/edit/reject)
 * and invokes the email-agent Lambda to continue the LangGraph flow.
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ResumeRequest {
  draft_id: string;
  thread_id: string;
  decision: 'approve' | 'edit' | 'reject';
  feedback?: string;
  edits?: Record<string, any>;
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

    // Parse request
    const body: ResumeRequest = await req.json();
    const { draft_id, thread_id, decision, feedback, edits } = body;

    // Validate input
    if (!draft_id || !thread_id || !decision) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: draft_id, thread_id, decision" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!['approve', 'edit', 'reject'].includes(decision)) {
      return new Response(
        JSON.stringify({ error: "Invalid decision. Must be: approve, edit, or reject" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get user ID from auth token
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

    // Update draft status based on decision
    const updateData: Record<string, any> = {
      approved_by: user.id,
      approved_at: new Date().toISOString(),
    };

    if (decision === 'approve') {
      updateData.approval_status = 'approved';
    } else if (decision === 'reject') {
      updateData.approval_status = 'rejected';
      updateData.rejection_reason = feedback || 'No reason provided';
    }
    // Note: 'edit' keeps approval_status as 'pending' for re-review

    const { error: updateError } = await supabase
      .from('email_drafts')
      .update(updateData)
      .eq('id', draft_id);

    if (updateError) {
      console.error('Error updating draft:', updateError);
      return new Response(
        JSON.stringify({ error: 'Failed to update draft status' }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Prepare payload for email-agent Lambda
    const lambdaPayload = {
      action: 'resume',
      thread_id,
      draft_id,
      decision,
      feedback,
      edits,
      user_id: user.id,
    };

    // Invoke email-agent Lambda
    const lambdaFunctionName = Deno.env.get("EMAIL_AGENT_LAMBDA_ARN") || "email-agent";

    console.log(`Invoking email-agent Lambda: ${lambdaFunctionName}`);
    console.log(`Payload: ${JSON.stringify(lambdaPayload)}`);

    try {
      // Use AWS SDK to invoke Lambda
      // Note: In production, configure AWS credentials via environment variables
      const AWS_REGION = Deno.env.get("AWS_REGION") || "us-east-1";
      const AWS_ACCESS_KEY_ID = Deno.env.get("AWS_ACCESS_KEY_ID");
      const AWS_SECRET_ACCESS_KEY = Deno.env.get("AWS_SECRET_ACCESS_KEY");

      if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY) {
        console.warn("AWS credentials not configured. Skipping Lambda invocation.");
        return new Response(
          JSON.stringify({
            status: 'success',
            message: 'Draft updated. Lambda invocation skipped (no AWS credentials).',
            draft_id,
            decision
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Invoke Lambda via HTTP endpoint (local or deployed)
      const lambdaUrl = Deno.env.get("EMAIL_AGENT_LAMBDA_URL");
      if (lambdaUrl) {
        const lambdaResponse = await fetch(lambdaUrl, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(lambdaPayload),
        });

        const lambdaResult = await lambdaResponse.json();
        console.log('Lambda response:', lambdaResult);

        return new Response(
          JSON.stringify({
            status: 'success',
            message: 'Draft updated and email-agent invoked',
            draft_id,
            decision,
            lambda_result: lambdaResult,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Fallback: Just update the draft without Lambda invocation
      return new Response(
        JSON.stringify({
          status: 'success',
          message: 'Draft updated. Lambda URL not configured.',
          draft_id,
          decision,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );

    } catch (lambdaError) {
      console.error('Error invoking Lambda:', lambdaError);
      return new Response(
        JSON.stringify({
          status: 'partial_success',
          message: 'Draft updated but failed to invoke email-agent',
          error: lambdaError.message,
          draft_id,
          decision,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

  } catch (error) {
    console.error('Error in email-agent-resume:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
