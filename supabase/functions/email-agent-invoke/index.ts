/**
 * Email Agent Invoke Edge Function
 *
 * Invokes the email-agent Lambda to generate a new email draft.
 * Used by the Emails page for AI-assisted replies and new email composition.
 *
 * Request body:
 * {
 *   action: 'draft',
 *   email_id?: string,           // Source email for reply context
 *   contact_id?: string,         // Contact being emailed
 *   from_mailbox_id: string,     // Mailbox with persona + signature
 *   conversation_id?: string,    // Conversation context
 *   thread_id?: string,          // Thread ID for context
 *   params: {
 *     email_purpose: string,     // User instructions
 *     tone?: string,             // professional, friendly, formal, concise
 *     product_ids?: string[],    // Products to reference
 *     template_id?: string,      // Optional template
 *   },
 *   source: {
 *     type: 'manual',            // Differentiates from workflow/campaign
 *     name: string,              // Source page/feature
 *   }
 * }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

interface InvokeRequest {
  action: 'draft';
  email_id?: string;
  contact_id?: string;
  from_mailbox_id: string;
  conversation_id?: string;
  thread_id?: string;
  params: {
    email_purpose: string;
    tone?: 'professional' | 'friendly' | 'formal' | 'concise';
    product_ids?: string[];
    template_id?: string;
    to?: string; // Recipient email for new emails (when contact not in DB)
  };
  source: {
    type: 'manual' | 'workflow' | 'campaign';
    name: string;
  };
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
    const body: InvokeRequest = await req.json();
    const { action, email_id, contact_id, from_mailbox_id, conversation_id, thread_id, params, source } = body;

    // Validate required fields
    if (action !== 'draft') {
      return new Response(
        JSON.stringify({ error: "Invalid action. Must be: draft" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!from_mailbox_id) {
      return new Response(
        JSON.stringify({ error: "Missing required field: from_mailbox_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!params?.email_purpose) {
      return new Response(
        JSON.stringify({ error: "Missing required field: params.email_purpose" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Log the action
    console.log(`User ${user.id} (${user.email}) invoking email-agent for draft generation`);
    console.log(`Params: ${JSON.stringify({ email_id, contact_id, from_mailbox_id, conversation_id, params, source })}`);

    // Verify mailbox exists and is active
    const { data: mailbox, error: mailboxError } = await supabase
      .from('mailboxes')
      .select('id, email, name, persona_description, signature_html, is_active')
      .eq('id', from_mailbox_id)
      .single();

    if (mailboxError || !mailbox) {
      return new Response(
        JSON.stringify({ error: "Mailbox not found", details: mailboxError }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!mailbox.is_active) {
      return new Response(
        JSON.stringify({ error: "Mailbox is not active" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Build Lambda payload
    //
    // The new email-agent LangGraph (plan→draft→review) owns context loading
    // via its `load_context` node — fetches thread, contact, sender_org,
    // recent drafts/executions, persona, instructions, mailbox itself.
    // We no longer pre-fetch contact + source_email here; the agent's loader
    // is the single source of truth and runs uniformly across all 3
    // invocation paths (workflow / manual / redraft).
    //
    // mailbox is_active validation above is preserved as an early gate so we
    // don't invoke Lambda for inactive mailboxes.
    const lambdaPayload = {
      action: 'draft',
      // Tells the Lambda graph which entry path / persistence semantics apply.
      invocation_context: 'manual',
      email_id,
      contact_id,
      from_mailbox_id,
      conversation_id,
      thread_id,
      params,
      // Kept for backward compat with any consumers still reading source.type;
      // new graph keys off invocation_context above.
      source: source || { type: 'manual', name: 'Emails Page' },
      created_by_user_id: user.id,
    };

    // Invoke email-agent Lambda - get URL from system_config
    const { data: configData, error: configError } = await supabase
      .from('system_config')
      .select('value')
      .eq('key', 'email_agent_url')
      .single();

    const lambdaUrl = configData?.value;
    if (configError || !lambdaUrl) {
      console.error("email_agent_url not found in system_config:", configError);
      return new Response(
        JSON.stringify({ error: "Email agent service not configured" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Invoking email-agent Lambda: ${lambdaUrl}`);
    console.log(`Payload: ${JSON.stringify(lambdaPayload)}`);

    try {
      const lambdaResponse = await fetch(lambdaUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(lambdaPayload),
      });

      const lambdaResult = await lambdaResponse.json();
      console.log('Lambda response:', lambdaResult);

      if (!lambdaResponse.ok) {
        return new Response(
          JSON.stringify({
            error: 'Email agent failed',
            details: lambdaResult,
          }),
          { status: lambdaResponse.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({
          status: 'success',
          message: 'Draft generation initiated',
          draft_id: lambdaResult.draft_id,
          ...lambdaResult,
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } catch (lambdaError) {
      console.error('Error invoking Lambda:', lambdaError);
      return new Response(
        JSON.stringify({
          error: 'Failed to invoke email agent',
          details: lambdaError.message,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

  } catch (error) {
    console.error('Error in email-agent-invoke:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
