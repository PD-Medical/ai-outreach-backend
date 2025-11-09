/**
 * Send Tracked Email via Resend
 * 
 * Sends emails via Resend with automatic engagement tracking
 * Supports bulk sending and personalization
 * 
 * Deploy: supabase functions deploy send-tracked-email
 * 
 * Usage:
 * POST /functions/v1/send-tracked-email
 * Body: {
 *   to: "customer@hospital.com",
 *   subject: "Product Launch",
 *   html: "Email content with tracking links...",
 *   campaign_name: "Product Launch 2025"
 * }
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

interface SendEmailRequest {
  to: string | string[];
  from?: string;
  subject: string;
  html: string;
  text?: string;
  campaign_name?: string;
  campaign_id?: string;
  tags?: Array<{ name: string; value: string }>;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  
  // Only allow POST
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { 
        status: 405, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
  
  try {
    console.log('[SendEmail] Starting email send via Resend');
    
    // Parse request
    const body: SendEmailRequest = await req.json();
    const { 
      to, 
      from = 'peter@pdmedical.com.au', 
      subject, 
      html, 
      text,
      campaign_name,
      campaign_id,
      tags = []
    } = body;
    
    if (!to || !subject || !html) {
      return new Response(
        JSON.stringify({ error: 'Missing required fields: to, subject, html' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }
    
    // Get Resend API key
    const resendApiKey = Deno.env.get('RESEND_API_KEY');
    if (!resendApiKey) {
      return new Response(
        JSON.stringify({ error: 'RESEND_API_KEY not configured' }),
        { 
          status: 500, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }
    
    // Create Supabase client
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );
    
    // Send email via Resend API
    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${resendApiKey}`
      },
      body: JSON.stringify({
        from,
        to: Array.isArray(to) ? to : [to],
        subject,
        html,
        text,
        tags: [
          ...tags,
          { name: 'source', value: 'supabase_edge_function' }
        ]
      })
    });
    
    const resendData = await resendResponse.json();
    
    if (!resendResponse.ok) {
      console.error('[SendEmail] Resend API error:', resendData);
      return new Response(
        JSON.stringify({ 
          error: 'Failed to send email', 
          details: resendData 
        }),
        { 
          status: resendResponse.status, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }
    
    console.log('[SendEmail] Email sent successfully:', resendData);
    
    // If campaign tracking is enabled, log to database
    if (campaign_name || campaign_id) {
      let dbCampaignId = campaign_id;
      
      // Create campaign if name provided but no ID
      if (campaign_name && !campaign_id) {
        const { data: campaign, error: campaignError } = await supabase
          .from('email_campaigns')
          .insert({
            name: campaign_name,
            subject: subject,
            status: 'sending',
            total_sent: Array.isArray(to) ? to.length : 1,
            sent_at: new Date().toISOString()
          })
          .select('id')
          .single();
        
        if (campaign && !campaignError) {
          dbCampaignId = campaign.id;
        }
      }
      
      // Update campaign with Resend email ID
      if (dbCampaignId && resendData.id) {
        await supabase
          .from('email_campaigns')
          .update({
            resend_email_ids: supabase.raw(`array_append(resend_email_ids, '${resendData.id}')`),
            updated_at: new Date().toISOString()
          })
          .eq('id', dbCampaignId);
      }
    }
    
    return new Response(
      JSON.stringify({
        success: true,
        email_id: resendData.id,
        message: 'Email sent successfully',
        recipients: Array.isArray(to) ? to.length : 1
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
    
  } catch (error) {
    console.error('[SendEmail] Error:', error);
    
    return new Response(
      JSON.stringify({
        error: error.message,
        stack: error.stack
      }),
      { 
        status: 500, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
});



