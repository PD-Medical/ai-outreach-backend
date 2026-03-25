/**
 * Email Agent Preview Edge Function
 *
 * Invokes the email-agent Lambda in preview mode to generate email content
 * WITHOUT saving to the database. Used for inline previews before sending
 * to the approval queue.
 *
 * Uses the same email-agent Lambda with full tool access (product search,
 * contact info, email thread, etc.) ensuring uniform AI capabilities.
 *
 * Request body:
 * {
 *   contact_id?: string,           // Contact for personalization
 *   email_id?: string,             // Source email for reply context
 *   from_mailbox_id: string,       // Mailbox with persona + signature
 *   conversation_id?: string,      // Conversation context
 *   params: {
 *     email_purpose: string,       // User instructions
 *     tone?: string,               // professional, friendly, formal, concise
 *     product_ids?: string[],      // Products to reference
 *   }
 * }
 *
 * Response:
 * {
 *   status: 'preview',
 *   subject: string,
 *   body: string,
 *   to_emails: string[],
 *   from_name?: string,
 *   from_email?: string,
 * }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface PreviewRequest {
  contact_id?: string;
  email_id?: string;
  from_mailbox_id: string;
  conversation_id?: string;
  params: {
    email_purpose: string;
    tone?: 'professional' | 'friendly' | 'formal' | 'concise';
    product_ids?: string[];
    to?: string; // Recipient email for new emails (when contact not in DB)
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
    const body: PreviewRequest = await req.json();
    const { contact_id, email_id, from_mailbox_id, conversation_id, params } = body;

    // Validate required fields
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

    // Get user ID from auth token (optional for preview, but good for logging)
    const authHeader = req.headers.get("Authorization");
    let userId = null;
    if (authHeader) {
      const token = authHeader.replace("Bearer ", "");
      const { data: { user } } = await supabase.auth.getUser(token);
      userId = user?.id;
    }

    console.log(`Preview request from user ${userId || 'anonymous'}`);
    console.log(`Params: ${JSON.stringify({ contact_id, email_id, from_mailbox_id, params })}`);

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

    // Get contact details if provided (for personalization context)
    let contactDetails = null;
    let recipientEmail = null;
    if (contact_id) {
      const { data: contact } = await supabase
        .from('contacts')
        .select(`
          id, email, first_name, last_name, job_title, department,
          organization:organizations(id, name, industry, city, state, facility_type)
        `)
        .eq('id', contact_id)
        .single();
      contactDetails = contact;
      recipientEmail = contact?.email;
    }

    // Use params.to if explicitly provided (for new emails to contacts not in DB)
    if (!recipientEmail && params.to) {
      recipientEmail = params.to;
      console.log(`Using params.to for recipient: ${recipientEmail}`);
    }

    // Get source email if provided (for reply context)
    let emailContext = null;
    if (email_id) {
      const { data: email } = await supabase
        .from('emails')
        .select('id, subject, from_email, from_name, body_plain, body_html, received_at, direction, thread_id')
        .eq('id', email_id)
        .single();
      emailContext = email;
      // For reply, use the sender's email as recipient
      if (email && !recipientEmail) {
        recipientEmail = email.from_email;
      }
    }

    // Build Lambda payload for preview action
    const lambdaPayload = {
      action: 'preview',  // Key difference from draft - uses preview_email_tool
      email_id,
      contact_id,
      from_mailbox_id,
      conversation_id,
      params: {
        ...params,
        // Include recipient if we found one
        to: recipientEmail,
        // Include mailbox context for persona/signature
        mailbox_persona: mailbox.persona_description,
        mailbox_signature: mailbox.signature_html,
      },
      // Include pre-fetched context to reduce Lambda lookups
      email_context: emailContext ? {
        id: emailContext.id,
        subject: emailContext.subject,
        from_email: emailContext.from_email,
        from_name: emailContext.from_name,
        body_plain: emailContext.body_plain?.substring(0, 2000), // Truncate
        thread_id: emailContext.thread_id,
      } : undefined,
      // Include contact context if available
      contact_context: contactDetails ? {
        id: contactDetails.id,
        email: contactDetails.email,
        first_name: contactDetails.first_name,
        last_name: contactDetails.last_name,
        job_title: contactDetails.job_title,
        organization: contactDetails.organization,
      } : undefined,
    };

    // Get Lambda URL from system_config
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

    console.log(`Invoking email-agent Lambda (preview): ${lambdaUrl}`);

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
            error: 'Email agent preview failed',
            details: lambdaResult,
          }),
          { status: lambdaResponse.status, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      // Parse Lambda result - it may be nested in body
      let previewData = lambdaResult;
      if (lambdaResult.body && typeof lambdaResult.body === 'string') {
        try {
          previewData = JSON.parse(lambdaResult.body);
        } catch {
          previewData = lambdaResult;
        }
      }

      return new Response(
        JSON.stringify({
          status: 'preview',
          subject: previewData.subject || '',
          body: previewData.body || '',
          to_emails: previewData.to_emails || (recipientEmail ? [recipientEmail] : []),
          from_name: previewData.from_name || mailbox.name,
          from_email: previewData.from_email || mailbox.email,
          // Include contact info for display
          contact: contactDetails ? {
            id: contactDetails.id,
            firstName: contactDetails.first_name,
            lastName: contactDetails.last_name,
            email: contactDetails.email,
            organizationName: contactDetails.organization?.name,
          } : null,
          // Include mailbox info
          mailbox: {
            id: mailbox.id,
            email: mailbox.email,
            name: mailbox.name,
          },
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } catch (lambdaError) {
      console.error('Error invoking Lambda:', lambdaError);
      return new Response(
        JSON.stringify({
          error: 'Failed to invoke email agent preview',
          details: lambdaError.message,
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

  } catch (error) {
    console.error('Error in email-agent-preview:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
