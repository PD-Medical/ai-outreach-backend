/**
 * Email Agent Resume Edge Function
 *
 * Handles user decisions on pending email drafts (approve/edit/reject/redraft).
 *
 * Simplified architecture - no LangGraph checkpointing:
 * - email_drafts table is the single source of truth
 * - Redraft loads context from previous draft's stored columns
 * - No thread_id needed for resume
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ResumeRequest {
  draft_id: string;
  decision: 'approve' | 'edit' | 'reject' | 'redraft';
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
    const { draft_id, decision, feedback, edits } = body;

    // Validate input - thread_id no longer required
    if (!draft_id || !decision) {
      return new Response(
        JSON.stringify({ error: "Missing required fields: draft_id, decision" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!['approve', 'edit', 'reject', 'redraft'].includes(decision)) {
      return new Response(
        JSON.stringify({ error: "Invalid decision. Must be: approve, edit, reject, or redraft" }),
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

    // Log the action with user info for traceability
    console.log(`User ${user.id} (${user.email}) requesting ${decision} for draft ${draft_id}`);

    // Check if user has a profile (for approved_by FK constraint)
    const { data: profile } = await supabase
      .from('profiles')
      .select('profile_id')
      .eq('profile_id', user.id)
      .single();

    const hasProfile = !!profile;

    // Update draft status based on decision
    const updateData: Record<string, any> = {};

    if (decision === 'approve') {
      updateData.approval_status = 'approved';
      if (hasProfile) updateData.approved_by = user.id;
      updateData.approved_at = new Date().toISOString();
    } else if (decision === 'reject') {
      // Reject = permanently discard, don't send
      updateData.approval_status = 'rejected';
      updateData.rejection_reason = feedback || 'Rejected by user';
      if (hasProfile) updateData.approved_by = user.id;
      updateData.approved_at = new Date().toISOString();
    } else if (decision === 'redraft') {
      // Redraft = mark current as rejected, AI will create new draft
      updateData.approval_status = 'rejected';
      updateData.rejection_reason = `Redraft requested: ${feedback || 'No feedback provided'}`;
      if (hasProfile) updateData.approved_by = user.id;
      updateData.approved_at = new Date().toISOString();
    }
    // Note: 'edit' doesn't update status - frontend updates directly then approves

    // Only update if there's something to update
    if (Object.keys(updateData).length > 0) {
      const { error: updateError } = await supabase
        .from('email_drafts')
        .update(updateData)
        .eq('id', draft_id);

      if (updateError) {
        console.error('Error updating draft:', updateError);
        return new Response(
          JSON.stringify({ error: 'Failed to update draft status', details: updateError }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // For redraft, invoke Lambda with simplified payload
    // Lambda will load all context from the draft's stored columns
    if (decision === 'redraft') {
      const lambdaUrl = Deno.env.get("EMAIL_AGENT_LAMBDA_URL");
      if (lambdaUrl) {
        // Simplified redraft payload - Lambda loads context from DB
        const lambdaPayload = {
          action: 'redraft',
          draft_id: draft_id,
          feedback: feedback || 'Please improve the draft',
        };

        console.log(`Invoking email-agent Lambda for redraft: ${lambdaUrl}`);
        console.log(`Payload: ${JSON.stringify(lambdaPayload)}`);

        try {
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
              message: 'Redraft requested - AI is creating a new draft',
              draft_id,
              decision,
              lambda_result: lambdaResult,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        } catch (lambdaError) {
          console.error('Error invoking Lambda for redraft:', lambdaError);
          return new Response(
            JSON.stringify({
              status: 'partial_success',
              message: 'Draft marked for redraft but failed to invoke AI agent',
              error: lambdaError.message,
              draft_id,
              decision,
            }),
            { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
      } else {
        console.warn("EMAIL_AGENT_LAMBDA_URL not configured. Cannot invoke redraft.");
        return new Response(
          JSON.stringify({
            status: 'partial_success',
            message: 'Draft marked for redraft. Lambda URL not configured - manual redraft may be needed.',
            draft_id,
            decision,
          }),
          { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    // For approve/reject/edit, no Lambda call needed
    // - approve: email sender edge function will pick up approved drafts
    // - reject: draft is marked as rejected, done
    // - edit: frontend handles edits directly, then calls approve

    // Default success response
    return new Response(
      JSON.stringify({
        status: 'success',
        message: `Draft ${decision}ed successfully`,
        draft_id,
        decision,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error('Error in email-agent-resume:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
