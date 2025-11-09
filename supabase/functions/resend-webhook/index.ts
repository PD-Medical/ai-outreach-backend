/**
 * Resend Webhook Handler
 * 
 * Receives webhooks from Resend for email engagement tracking
 * Processes 11 types of engagement signals and calculates scores
 * Triggers automated actions for high-priority events
 * 
 * Deploy: supabase functions deploy resend-webhook
 * 
 * Webhook URL: https://your-project.supabase.co/functions/v1/resend-webhook
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, svix-id, svix-timestamp, svix-signature',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// ============================================================================
// ENGAGEMENT SIGNAL CONFIGURATIONS
// ============================================================================

interface SignalConfig {
  type: string;
  score: number;
  priority: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  actions: string[];
  description: string;
}

const ENGAGEMENT_SIGNALS: Record<string, SignalConfig> = {
  pricing_click: {
    type: 'pricing_click',
    score: 10,
    priority: 'HIGH',
    actions: ['sales_notification', 'quote_prep', 'hot_lead_flag'],
    description: 'Clicked Pricing/Quote Link - High buying intent'
  },
  product_click: {
    type: 'product_click',
    score: 8,
    priority: 'MEDIUM',
    actions: ['segment_added', 'follow_up_scheduled'],
    description: 'Clicked Product Page Link - Active research'
  },
  attachment_download: {
    type: 'attachment_download',
    score: 8,
    priority: 'MEDIUM',
    actions: ['nurture_enrolled', 'content_sent'],
    description: 'Downloaded PDF/Attachment - Active research'
  },
  multiple_opens: {
    type: 'multiple_opens',
    score: 7,
    priority: 'MEDIUM',
    actions: ['hot_lead_flag', 'sales_notification'],
    description: 'Opened Email 3+ Times - Strong interest'
  },
  case_study_click: {
    type: 'case_study_click',
    score: 6,
    priority: 'MEDIUM',
    actions: ['content_sent', 'segment_added'],
    description: 'Clicked Case Study Link - Validation phase'
  },
  email_opened: {
    type: 'email_opened',
    score: 5,
    priority: 'LOW',
    actions: ['follow_up_scheduled'],
    description: 'Email Opened - First time'
  },
  quick_open: {
    type: 'quick_open',
    score: 3,
    priority: 'LOW',
    actions: [],
    description: 'Opened Within 1 Hour - Highly responsive'
  },
  mobile_open: {
    type: 'mobile_open',
    score: 2,
    priority: 'LOW',
    actions: [],
    description: 'Opened on Mobile Device'
  },
  unsubscribe: {
    type: 'unsubscribe',
    score: -50,
    priority: 'CRITICAL',
    actions: ['suppression'],
    description: 'Clicked Unsubscribe Link - LEGAL: Suppress immediately'
  },
  spam_report: {
    type: 'spam_report',
    score: -30,
    priority: 'CRITICAL',
    actions: ['suppression'],
    description: 'Marked Email as Spam - Damages sender reputation'
  },
  not_opened: {
    type: 'not_opened',
    score: 0,
    priority: 'LOW',
    actions: [],
    description: 'Delivered but Not Opened after 7 days'
  }
};

// ============================================================================
// RESEND EVENT TYPE MAPPING
// ============================================================================

/**
 * Map Resend event types to our engagement signals
 */
function mapResendEventToSignal(
  event: any,
  openCount: number = 1,
  timeSinceDelivery: number = 0
): SignalConfig | null {
  const eventType = event.type;
  
  switch (eventType) {
    case 'email.opened':
      // Check for multiple opens (3+)
      if (openCount >= 3) {
        return ENGAGEMENT_SIGNALS.multiple_opens;
      }
      // Check for quick open (<1 hour)
      if (timeSinceDelivery > 0 && timeSinceDelivery < 3600000) { // 1 hour in ms
        return ENGAGEMENT_SIGNALS.quick_open;
      }
      // Check for mobile open
      const userAgent = event.data?.user_agent || '';
      if (userAgent && (userAgent.includes('Mobile') || userAgent.includes('Android') || userAgent.includes('iPhone'))) {
        return ENGAGEMENT_SIGNALS.mobile_open;
      }
      return ENGAGEMENT_SIGNALS.email_opened;
    
    case 'email.clicked':
      const clickUrl = event.data?.click?.link || '';
      // Check for pricing link
      if (clickUrl.match(/pricing|quote|price|buy|purchase|order/i)) {
        return ENGAGEMENT_SIGNALS.pricing_click;
      }
      // Check for case study link
      if (clickUrl.match(/case-study|testimonial|success-story|customer-story/i)) {
        return ENGAGEMENT_SIGNALS.case_study_click;
      }
      // Check for attachment/download link
      if (clickUrl.match(/download|attachment|pdf|brochure|catalog/i)) {
        return ENGAGEMENT_SIGNALS.attachment_download;
      }
      // Default to product click
      return ENGAGEMENT_SIGNALS.product_click;
    
    case 'email.complained':
    case 'email.spam_complaint':
      return ENGAGEMENT_SIGNALS.spam_report;
    
    case 'email.unsubscribed':
      return ENGAGEMENT_SIGNALS.unsubscribe;
    
    default:
      return null;
  }
}

// ============================================================================
// DATABASE OPERATIONS
// ============================================================================

/**
 * Find or create contact by email
 */
async function findOrCreateContact(supabase: any, email: string): Promise<string | null> {
  try {
    // First, try to find existing contact
    const { data: existingContact, error: findError } = await supabase
      .from('contacts')
      .select('id')
      .eq('email', email)
      .single();
    
    if (existingContact) {
      return existingContact.id;
    }
    
    // If not found, check if we should create one
    // For now, we'll just log it - you can decide if you want to auto-create contacts
    console.log(`[Webhook] Contact not found for email: ${email}`);
    return null;
  } catch (error) {
    console.error('[Webhook] Error finding contact:', error);
    return null;
  }
}

/**
 * Get open count for an email
 */
async function getOpenCount(supabase: any, resendEmailId: string): Promise<number> {
  const { data, error } = await supabase
    .from('engagement_signals')
    .select('id')
    .eq('resend_email_id', resendEmailId)
    .in('signal_type', ['email_opened', 'quick_open', 'mobile_open', 'multiple_opens']);
  
  return data ? data.length : 0;
}

/**
 * Insert engagement signal
 */
async function insertEngagementSignal(
  supabase: any,
  data: {
    contactId: string | null;
    email: string;
    resendEventId: string;
    resendEmailId: string;
    signalType: string;
    scoreValue: number;
    priority: string;
    eventData: any;
    linkUrl?: string;
    deviceType?: string;
    userAgent?: string;
    ipAddress?: string;
    eventTimestamp: string;
  }
) {
  const { error } = await supabase
    .from('engagement_signals')
    .insert({
      contact_id: data.contactId,
      email: data.email,
      resend_event_id: data.resendEventId,
      resend_email_id: data.resendEmailId,
      signal_type: data.signalType,
      score_value: data.scoreValue,
      priority: data.priority,
      event_data: data.eventData,
      link_url: data.linkUrl,
      device_type: data.deviceType,
      user_agent: data.userAgent,
      ip_address: data.ipAddress,
      event_timestamp: data.eventTimestamp,
      processed_at: new Date().toISOString()
    });
  
  if (error) {
    console.error('[Webhook] Error inserting engagement signal:', error);
    throw error;
  }
}

/**
 * Trigger automated actions
 */
async function triggerAutomatedActions(
  supabase: any,
  signalId: string,
  contactId: string,
  actions: string[],
  signalType: string
) {
  if (!contactId || actions.length === 0) {
    return;
  }
  
  const actionPromises = actions.map(async (actionType) => {
    let actionDescription = '';
    let actionData: any = {};
    
    switch (actionType) {
      case 'sales_notification':
        actionDescription = 'Sales team notified of high-intent engagement';
        actionData = { 
          notification_type: 'email',
          urgency: 'high',
          signal_type: signalType
        };
        break;
      
      case 'quote_prep':
        actionDescription = 'Quote preparation workflow triggered';
        actionData = { 
          workflow: 'quote_preparation',
          priority: 'high'
        };
        break;
      
      case 'hot_lead_flag':
        actionDescription = 'Contact flagged as hot lead';
        actionData = { 
          flag: 'hot_lead',
          reason: signalType
        };
        break;
      
      case 'segment_added':
        actionDescription = `Added to ${signalType} segment`;
        actionData = { 
          segment: signalType,
          auto_added: true
        };
        break;
      
      case 'follow_up_scheduled':
        actionDescription = 'Follow-up email scheduled';
        actionData = { 
          schedule_days: 2,
          type: 'follow_up'
        };
        break;
      
      case 'nurture_enrolled':
        actionDescription = 'Enrolled in nurture track';
        actionData = { 
          track: 'product_nurture',
          trigger: signalType
        };
        break;
      
      case 'content_sent':
        actionDescription = 'Related content sent';
        actionData = { 
          content_type: 'related',
          trigger: signalType
        };
        break;
      
      case 'suppression':
        actionDescription = 'Contact suppressed - unsubscribed or spam';
        actionData = { 
          suppression_reason: signalType,
          suppression_date: new Date().toISOString()
        };
        
        // Update contact status
        await supabase
          .from('contacts')
          .update({ 
            status: signalType === 'spam_report' ? 'bounced' : 'unsubscribed'
          })
          .eq('id', contactId);
        break;
    }
    
    // Log the automated action
    await supabase
      .from('automated_actions_log')
      .insert({
        engagement_signal_id: signalId,
        contact_id: contactId,
        action_type: actionType,
        action_description: actionDescription,
        action_data: actionData,
        status: 'pending',
        triggered_at: new Date().toISOString()
      });
  });
  
  await Promise.all(actionPromises);
}

// ============================================================================
// WEBHOOK HANDLER
// ============================================================================

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }
  
  // Handle GET requests for webhook verification (some services send GET to verify)
  if (req.method === 'GET') {
    return new Response(
      JSON.stringify({ 
        success: true,
        message: 'Resend webhook endpoint is active',
        timestamp: new Date().toISOString()
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
  }
  
  // Only allow POST for actual webhooks
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
    console.log('[Webhook] Received Resend webhook');
    
    // Parse webhook payload
    const payload = await req.json();
    console.log('[Webhook] Payload:', JSON.stringify(payload, null, 2));
    
    // Create Supabase client with service role (bypasses RLS)
    // This is safe because we're not exposing user data - just receiving webhooks
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    
    if (!supabaseUrl || !supabaseServiceKey) {
      throw new Error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY environment variables');
    }
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });
    
    // Extract event data
    const event = payload;
    const eventType = event.type;
    const eventId = event.created_at ? `${eventType}_${event.created_at}` : `${eventType}_${Date.now()}`;
    const emailData = event.data || {};
    const recipientEmail = emailData.email || emailData.to || '';
    const resendEmailId = emailData.email_id || event.email_id || '';
    
    if (!recipientEmail) {
      console.error('[Webhook] No recipient email found in payload');
      return new Response(
        JSON.stringify({ error: 'No recipient email found' }),
        { 
          status: 400, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }
    
    console.log(`[Webhook] Processing ${eventType} for ${recipientEmail}`);
    
    // Find or create contact
    const contactId = await findOrCreateContact(supabase, recipientEmail);
    
    // Get open count for multiple opens detection
    const openCount = await getOpenCount(supabase, resendEmailId);
    
    // Calculate time since delivery (if available)
    const deliveredAt = emailData.delivered_at ? new Date(emailData.delivered_at).getTime() : 0;
    const eventTime = event.created_at ? new Date(event.created_at).getTime() : Date.now();
    const timeSinceDelivery = deliveredAt ? eventTime - deliveredAt : 0;
    
    // Map Resend event to engagement signal
    const signal = mapResendEventToSignal(event, openCount + 1, timeSinceDelivery);
    
    if (!signal) {
      console.log(`[Webhook] No mapping for event type: ${eventType}`);
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'Event received but not mapped to engagement signal' 
        }),
        { 
          status: 200, 
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      );
    }
    
    console.log(`[Webhook] Mapped to signal: ${signal.type} (score: ${signal.score}, priority: ${signal.priority})`);
    
    // Extract additional metadata
    const linkUrl = emailData.click?.link || '';
    const userAgent = emailData.user_agent || '';
    const deviceType = userAgent.includes('Mobile') ? 'mobile' : 
                      userAgent.includes('Tablet') ? 'tablet' : 'desktop';
    const ipAddress = emailData.ip_address || '';
    
    // Insert engagement signal
    await insertEngagementSignal(supabase, {
      contactId,
      email: recipientEmail,
      resendEventId: eventId,
      resendEmailId,
      signalType: signal.type,
      scoreValue: signal.score,
      priority: signal.priority,
      eventData: payload,
      linkUrl,
      deviceType,
      userAgent,
      ipAddress,
      eventTimestamp: new Date(event.created_at || Date.now()).toISOString()
    });
    
    // Get the signal ID we just inserted
    const { data: insertedSignal } = await supabase
      .from('engagement_signals')
      .select('id')
      .eq('resend_event_id', eventId)
      .single();
    
    // Trigger automated actions
    if (insertedSignal && contactId) {
      await triggerAutomatedActions(
        supabase,
        insertedSignal.id,
        contactId,
        signal.actions,
        signal.type
      );
    }
    
    console.log(`[Webhook] Successfully processed ${signal.type} for ${recipientEmail}`);
    
    return new Response(
      JSON.stringify({
        success: true,
        signal_type: signal.type,
        score: signal.score,
        priority: signal.priority,
        actions_triggered: signal.actions.length,
        contact_id: contactId
      }),
      { 
        status: 200, 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    );
    
  } catch (error) {
    console.error('[Webhook] Error processing webhook:', error);
    
    return new Response(
      JSON.stringify({
        success: false,
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

