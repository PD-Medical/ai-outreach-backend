/**
 * Email Template Generate Edge Function
 *
 * Generates an email TEMPLATE with merge fields using the email-agent Lambda.
 * Uses the full agent capabilities including:
 * - Product search and info tools
 * - Contact/organization field analysis
 * - Intelligent merge field selection based on data population
 *
 * Request body:
 * {
 *   emailPurpose: string,       // User instructions for AI
 *   productIds?: string[],      // Products to include context for
 *   fromMailboxId: string,      // Mailbox for sender persona
 *   sampleContactId?: string,   // Optional sample contact for preview
 *   contactIds?: string[],      // Target contacts for field analysis
 *   campaignId?: string,        // Optional campaign to save template to
 *   feedback?: string,          // Regeneration feedback
 * }
 *
 * Response:
 * {
 *   success: boolean,
 *   data?: {
 *     subject: string,          // Template with merge fields
 *     body: string,             // Template with merge fields
 *     mergeFieldsUsed: string[],// Which fields AI used
 *     reasoning?: string,       // AI's reasoning for choices
 *     samplePreview?: {         // Rendered with sample contact
 *       subject: string,
 *       body: string,
 *     }
 *   },
 *   error?: string
 * }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Supported merge fields matching variable_resolver.py
const SUPPORTED_MERGE_FIELDS = [
  // Contact fields
  { field: 'first_name', description: 'Contact first name', example: 'Sarah' },
  { field: 'last_name', description: 'Contact last name', example: 'Johnson' },
  { field: 'full_name', description: 'Full name (first + last)', example: 'Sarah Johnson' },
  { field: 'job_title', description: 'Contact job title', example: 'Infection Control Nurse' },
  { field: 'department', description: 'Contact department', example: 'Infection Control' },
  // Organization fields
  { field: 'company', description: 'Organization name', example: 'Royal Melbourne Hospital' },
  { field: 'organization_name', description: 'Organization name (alias)', example: 'Royal Melbourne Hospital' },
  { field: 'industry', description: 'Organization industry', example: 'Healthcare' },
  { field: 'city', description: 'Organization city', example: 'Melbourne' },
  { field: 'state', description: 'Organization state', example: 'VIC' },
  { field: 'region', description: 'Organization region', example: 'Metro' },
  { field: 'facility_type', description: 'Facility type', example: 'Public Hospital' },
  { field: 'hospital_category', description: 'Hospital category', example: 'Tertiary' },
];

interface TemplateRequest {
  emailPurpose: string;
  productIds?: string[];
  fromMailboxId: string;
  sampleContactId?: string;
  contactIds?: string[];
  campaignId?: string;
  feedback?: string;
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
    const body: TemplateRequest = await req.json();
    const { emailPurpose, productIds, fromMailboxId, sampleContactId, contactIds, campaignId, feedback } = body;

    // Validate required fields
    if (!emailPurpose || !fromMailboxId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing required fields: emailPurpose, fromMailboxId"
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch mailbox for sender persona (for signature append and preview info)
    const { data: mailbox, error: mailboxError } = await supabase
      .from('mailboxes')
      .select('id, email, name, persona_description, signature_html')
      .eq('id', fromMailboxId)
      .single();

    if (mailboxError || !mailbox) {
      return new Response(
        JSON.stringify({ success: false, error: "Mailbox not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch sample contact if provided (for preview generation)
    let sampleContact = null;
    if (sampleContactId) {
      const { data: contact } = await supabase
        .from('contacts')
        .select(`
          id,
          email,
          first_name,
          last_name,
          job_title,
          department,
          organization:organizations(
            id,
            name,
            industry,
            hospital_category,
            facility_type,
            state,
            city,
            region
          )
        `)
        .eq('id', sampleContactId)
        .single();
      sampleContact = contact;
    }

    // Get email-agent Lambda URL from system_config
    const { data: configData, error: configError } = await supabase
      .from('system_config')
      .select('value')
      .eq('key', 'email_agent_url')
      .single();

    const lambdaUrl = configData?.value;
    if (configError || !lambdaUrl) {
      console.error("email_agent_url not found in system_config:", configError);
      return new Response(
        JSON.stringify({ success: false, error: "Email agent service not configured" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Invoking email-agent Lambda (template mode): ${lambdaUrl}`);

    // Build Lambda payload for template action
    const lambdaPayload = {
      action: 'template',
      contact_ids: contactIds || [],  // For analyze_audience_fields_tool
      product_ids: productIds || [],
      params: {
        email_purpose: emailPurpose,
        feedback: feedback,
        // Include mailbox persona for context
        mailbox_name: mailbox.name,
        mailbox_email: mailbox.email,
        mailbox_persona: mailbox.persona_description,
      },
    };

    // Invoke Lambda
    const lambdaResponse = await fetch(lambdaUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(lambdaPayload),
    });

    const lambdaResult = await lambdaResponse.json();
    console.log('Lambda response status:', lambdaResponse.status);

    if (!lambdaResponse.ok) {
      console.error('Lambda error:', lambdaResult);
      return new Response(
        JSON.stringify({ success: false, error: "Template generation failed", details: lambdaResult }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse Lambda result - it may be nested in body
    let templateData = lambdaResult;
    if (lambdaResult.body && typeof lambdaResult.body === 'string') {
      try {
        templateData = JSON.parse(lambdaResult.body);
      } catch {
        templateData = lambdaResult;
      }
    }

    // Extract template content
    const subject = templateData.subject || '';
    let templateBody = templateData.body || '';
    const mergeFieldsUsed = templateData.merge_fields_used || [];
    const reasoning = templateData.reasoning;

    if (!subject && !templateBody) {
      return new Response(
        JSON.stringify({ success: false, error: "No template content generated", raw: templateData }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Append signature if mailbox has one
    if (mailbox.signature_html) {
      const plainSignature = mailbox.signature_html
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/p>/gi, '\n')
        .replace(/<\/div>/gi, '\n')
        .replace(/<[^>]+>/g, '')
        .replace(/&nbsp;/g, ' ')
        .replace(/&amp;/g, '&')
        .trim();
      templateBody += `\n\n${plainSignature}`;
    }

    // Generate sample preview if sample contact provided
    let samplePreview = undefined;
    if (sampleContact) {
      const org = sampleContact.organization as any;
      const fieldValues: Record<string, string> = {
        first_name: sampleContact.first_name || 'there',
        last_name: sampleContact.last_name || '',
        full_name: `${sampleContact.first_name || ''} ${sampleContact.last_name || ''}`.trim() || 'there',
        job_title: sampleContact.job_title || '',
        department: sampleContact.department || '',
        company: org?.name || 'your organization',
        organization_name: org?.name || 'your organization',
        industry: org?.industry || '',
        city: org?.city || '',
        state: org?.state || '',
        region: org?.region || '',
        facility_type: org?.facility_type || '',
        hospital_category: org?.hospital_category || '',
      };

      const renderTemplate = (template: string): string => {
        return template.replace(/\{(\w+)\}/g, (match, fieldName) => {
          return fieldValues[fieldName] || match;
        });
      };

      samplePreview = {
        subject: renderTemplate(subject),
        body: renderTemplate(templateBody),
      };
    }

    // Save to campaign if campaignId provided
    if (campaignId) {
      await supabase
        .from('campaign_sequences')
        .update({
          email_template_subject: subject,
          email_template_body: templateBody,
          template_status: 'pending_approval',
          template_generated_at: new Date().toISOString(),
        })
        .eq('id', campaignId);
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          subject: subject,
          body: templateBody,
          mergeFieldsUsed: mergeFieldsUsed,
          reasoning: reasoning,
          samplePreview,
        }
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error in email-template-generate:", error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
