/**
 * Email Preview Generate Edge Function
 *
 * Generates a PREVIEW email using AI without saving to database.
 * Used by campaign builder to show sample AI-generated email.
 *
 * Request body:
 * {
 *   contactId: string,       // Contact to personalize for
 *   emailPurpose: string,    // User instructions for AI
 *   productIds?: string[],   // Products to include context for
 *   fromMailboxId: string,   // Mailbox for sender info
 * }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface PreviewRequest {
  contactId: string;
  emailPurpose: string;
  productIds?: string[];
  fromMailboxId: string;
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
    const { contactId, emailPurpose, productIds, fromMailboxId } = body;

    // Validate required fields
    if (!contactId || !emailPurpose || !fromMailboxId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing required fields: contactId, emailPurpose, fromMailboxId"
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch contact details
    const { data: contact, error: contactError } = await supabase
      .from('contacts')
      .select(`
        id,
        email,
        first_name,
        last_name,
        job_title,
        department,
        lead_classification,
        engagement_level,
        organization:organizations(
          id,
          name,
          domain,
          industry,
          hospital_category,
          facility_type,
          state,
          city
        )
      `)
      .eq('id', contactId)
      .single();

    if (contactError || !contact) {
      return new Response(
        JSON.stringify({ success: false, error: "Contact not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch mailbox for sender info
    console.log("Looking up mailbox with ID:", fromMailboxId);
    const { data: mailbox, error: mailboxError } = await supabase
      .from('mailboxes')
      .select('id, email, name, persona_description, signature_html')
      .eq('id', fromMailboxId)
      .single();

    if (mailboxError || !mailbox) {
      console.error("Mailbox lookup failed:", { mailboxError, fromMailboxId });
      return new Response(
        JSON.stringify({
          success: false,
          error: "Mailbox not found",
          details: mailboxError?.message || "No mailbox with this ID",
          requestedId: fromMailboxId
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    console.log("Found mailbox:", mailbox.email);

    // Fetch product info if provided
    let productContext = "";
    if (productIds && productIds.length > 0) {
      const { data: products, error: productsError } = await supabase
        .from('products')
        .select('id, product_name, product_code, main_category, subcategory, market_potential, sales_instructions')
        .in('id', productIds);

      console.log("Products lookup:", { productIds, products, productsError });

      if (products && products.length > 0) {
        productContext = "\n\nPRODUCT INFORMATION TO INCLUDE:\n" +
          products.map(p =>
            `- ${p.product_name} (${p.product_code})\n  Category: ${p.main_category} > ${p.subcategory}\n  Market Info: ${p.market_potential || 'General medical equipment'}\n  Sales Notes: ${p.sales_instructions || 'None'}`
          ).join("\n\n");
      }
    }

    // Build the prompt for AI
    const org = contact.organization as any;
    const prompt = `You are writing a personalized sales email for PD Medical, a medical equipment supplier.

RECIPIENT INFORMATION:
- Name: ${contact.first_name} ${contact.last_name}
- Email: ${contact.email}
- Job Title: ${contact.job_title || 'Unknown'}
- Department: ${contact.department || 'Unknown'}
- Organization: ${org?.name || 'Unknown'}
- Organization Type: ${org?.hospital_category || 'Unknown'} ${org?.facility_type || 'Hospital'}
- Location: ${org?.city || ''}, ${org?.state || 'Australia'}
- Lead Status: ${contact.lead_classification || 'unknown'} lead, ${contact.engagement_level || 'unknown'} engagement

SENDER INFORMATION:
- Name: ${mailbox.name || 'Sales Team'}
- Email: ${mailbox.email}
${mailbox.persona_description ? `- Persona: ${mailbox.persona_description}` : ''}

EMAIL PURPOSE (from user):
${emailPurpose}
${productContext}

INSTRUCTIONS:
1. Write a personalized, professional email that sounds natural and human
2. Reference the recipient's organization and role where appropriate
3. Keep it concise but compelling (150-300 words ideal)
4. Include a clear call-to-action
5. Use Australian English spelling
6. Do NOT use generic phrases like "I hope this email finds you well"
7. Make it specific to their industry/role

IMPORTANT: Return ONLY valid JSON in this exact format:
{
  "subject": "Your compelling subject line here",
  "body": "Your email body here with proper line breaks using \\n"
}`;

    // Call OpenRouter API
    const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");
    if (!openRouterKey) {
      return new Response(
        JSON.stringify({ success: false, error: "AI service not configured" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Use DEFAULT_LLM_MODEL from env, fallback to Grok
    const model = Deno.env.get("DEFAULT_LLM_MODEL") || "x-ai/grok-4-fast";

    const aiResponse = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openRouterKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://pdmedical.com.au",
        "X-Title": "PD Medical Campaign Preview"
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
    let emailData;
    try {
      // Try to extract JSON from the response (in case there's extra text)
      const jsonMatch = content.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        emailData = JSON.parse(jsonMatch[0]);
      } else {
        throw new Error("No JSON found in response");
      }
    } catch (parseError) {
      console.error("Failed to parse AI response:", content);
      // Fallback: treat the whole response as the body
      emailData = {
        subject: `Re: ${emailPurpose.slice(0, 50)}`,
        body: content
      };
    }

    // Append signature if mailbox has one (convert HTML to plain text for preview)
    if (mailbox.signature_html) {
      // Strip HTML tags for plain text preview, keep basic structure
      const plainSignature = mailbox.signature_html
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/p>/gi, '\n')
        .replace(/<\/div>/gi, '\n')
        .replace(/<[^>]+>/g, '')
        .replace(/&nbsp;/g, ' ')
        .replace(/&amp;/g, '&')
        .trim();
      emailData.body += `\n\n${plainSignature}`;
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          subject: emailData.subject,
          body: emailData.body,
          contact: {
            id: contact.id,
            firstName: contact.first_name,
            lastName: contact.last_name,
            email: contact.email,
            organizationName: org?.name,
          },
          mailbox: {
            id: mailbox.id,
            email: mailbox.email,
            name: mailbox.name,
          }
        }
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (error) {
    console.error("Error in email-preview-generate:", error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
