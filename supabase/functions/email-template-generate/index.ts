/**
 * Email Template Generate Edge Function
 *
 * Generates an email TEMPLATE with merge fields using AI.
 * Used by campaign builder to create a single template that gets
 * personalized for each contact via field substitution.
 *
 * Request body:
 * {
 *   emailPurpose: string,       // User instructions for AI
 *   productIds?: string[],      // Products to include context for
 *   fromMailboxId: string,      // Mailbox for sender persona
 *   sampleContactId?: string,   // Optional sample contact for preview
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
    const { emailPurpose, productIds, fromMailboxId, sampleContactId, campaignId, feedback } = body;

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

    // Fetch mailbox for sender persona
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

    // Fetch product info if provided
    let productContext = "";
    if (productIds && productIds.length > 0) {
      const { data: products } = await supabase
        .from('products')
        .select('id, product_name, product_code, main_category, subcategory, market_potential, sales_instructions')
        .in('id', productIds);

      if (products && products.length > 0) {
        productContext = "\n\nPRODUCT INFORMATION TO INCLUDE:\n" +
          products.map(p =>
            `- ${p.product_name} (${p.product_code})\n  Category: ${p.main_category} > ${p.subcategory}\n  Market Info: ${p.market_potential || 'General medical equipment'}\n  Sales Notes: ${p.sales_instructions || 'None'}`
          ).join("\n\n");
      }
    }

    // Build the prompt for AI to generate a TEMPLATE with merge fields
    const mergeFieldsList = SUPPORTED_MERGE_FIELDS
      .map(f => `- {${f.field}} - ${f.description} (e.g., "${f.example}")`)
      .join('\n');

    const prompt = `You are creating an email TEMPLATE for a sales campaign at PD Medical, a medical equipment supplier.

This template will be used to send emails to MULTIPLE contacts, so you MUST use merge fields (placeholders) that will be replaced with each contact's actual data.

AVAILABLE MERGE FIELDS (use single curly braces):
${mergeFieldsList}

SENDER INFORMATION:
- Name: ${mailbox.name || 'Sales Team'}
- Email: ${mailbox.email}
${mailbox.persona_description ? `- Persona: ${mailbox.persona_description}` : ''}

EMAIL PURPOSE (from user):
${emailPurpose}
${productContext}
${feedback ? `\nFEEDBACK FOR IMPROVEMENT:\n${feedback}` : ''}

TEMPLATE INSTRUCTIONS:
1. Use merge fields like {first_name}, {company}, etc. for personalization
2. At minimum, use {first_name} in the greeting (e.g., "Hi {first_name},")
3. Reference {company} or {organization_name} where appropriate for context
4. Keep it concise but compelling (150-300 words ideal)
5. Include a clear call-to-action
6. Use Australian English spelling
7. Do NOT use generic phrases like "I hope this email finds you well"
8. Make it specific to medical/healthcare industry
9. The template should work for ANY contact when fields are substituted

EXAMPLE of proper merge field usage:
"Hi {first_name},

I noticed {company} is focused on infection control, and wanted to reach out about our latest solutions.

As {job_title} at {company}, you understand the importance of..."

IMPORTANT: Return ONLY valid JSON in this exact format:
{
  "subject": "Subject line with optional {merge_fields}",
  "body": "Email body with {merge_fields} for personalization. Use \\n for line breaks."
}`;

    // Call OpenRouter API
    const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!openRouterKey) {
      return new Response(
        JSON.stringify({ success: false, error: "AI service not configured" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const model = Deno.env.get("DEFAULT_LLM_MODEL") || "x-ai/grok-4-fast";

    const aiResponse = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openRouterKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://pdmedical.com.au",
        "X-Title": "PD Medical Template Generator"
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "user", content: prompt }
        ],
        max_tokens: 1000,
        temperature: 0.7,
      })
    });

    if (!aiResponse.ok) {
      const errorText = await aiResponse.text();
      console.error("OpenRouter API error:", errorText);
      return new Response(
        JSON.stringify({ success: false, error: "AI generation failed" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const aiResult = await aiResponse.json();
    const content = aiResult.choices?.[0]?.message?.content;

    if (!content) {
      return new Response(
        JSON.stringify({ success: false, error: "No content generated" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse the JSON response
    let templateData;
    try {
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        templateData = JSON.parse(jsonMatch[0]);
      } else {
        throw new Error("No JSON found in response");
      }
    } catch (parseError) {
      console.error("Failed to parse AI response:", content);
      return new Response(
        JSON.stringify({ success: false, error: "Failed to parse AI response" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Extract which merge fields were used
    const mergeFieldPattern = /\{(\w+)\}/g;
    const usedFields = new Set<string>();
    let match;
    const fullTemplate = templateData.subject + " " + templateData.body;
    while ((match = mergeFieldPattern.exec(fullTemplate)) !== null) {
      const fieldName = match[1];
      if (SUPPORTED_MERGE_FIELDS.some(f => f.field === fieldName)) {
        usedFields.add(fieldName);
      }
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
      templateData.body += `\n\n${plainSignature}`;
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
        subject: renderTemplate(templateData.subject),
        body: renderTemplate(templateData.body),
      };
    }

    // Save to campaign if campaignId provided
    if (campaignId) {
      await supabase
        .from('campaign_sequences')
        .update({
          email_template_subject: templateData.subject,
          email_template_body: templateData.body,
          template_status: 'pending_approval',
          template_generated_at: new Date().toISOString(),
        })
        .eq('id', campaignId);
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          subject: templateData.subject,
          body: templateData.body,
          mergeFieldsUsed: Array.from(usedFields),
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
