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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

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

    // Get contact details if provided
    let contactDetails = null;
    if (contact_id) {
      const { data: contact } = await supabase
        .from('contacts')
        .select('id, email, first_name, last_name, job_title, organization_id')
        .eq('id', contact_id)
        .single();
      contactDetails = contact;
    }

    // Get source email if provided
    let emailContext = null;
    if (email_id) {
      const { data: email } = await supabase
        .from('emails')
        .select('id, subject, from_email, from_name, body_plain, body_html, received_at, direction')
        .eq('id', email_id)
        .single();
      emailContext = email;
    }

    // Build Lambda payload
    const lambdaPayload = {
      action: 'draft',
      email_id,
      contact_id,
      from_mailbox_id,
      conversation_id,
      thread_id,
      params: {
        ...params,
        // Include mailbox context for persona/signature
        mailbox_persona: mailbox.persona_description,
        mailbox_signature: mailbox.signature_html,
      },
      source: source || { type: 'manual', name: 'Emails Page' },
      // Include pre-fetched context to reduce Lambda lookups
      context: {
        mailbox: {
          id: mailbox.id,
          email: mailbox.email,
          name: mailbox.name,
        },
        contact: contactDetails,
        source_email: emailContext,
      },
      // User who initiated the request
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
