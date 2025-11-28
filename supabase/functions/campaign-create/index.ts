/**
 * Campaign Create Edge Function
 *
 * Creates a new campaign sequence with target selection configuration.
 * Optionally starts immediate enrollment based on schedule.
 *
 * Deploy: supabase functions deploy campaign-create
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders, handleCors } from "../_shared/cors.ts";

// Types
interface FilterConfig {
  leadClassification?: string[];
  engagementLevel?: string[];
  status?: string[];
  tags?: string[];
  departments?: string[];
  leadScoreRange?: { min: number | null; max: number | null };
  regions?: string[];
  states?: string[];
  hospitalCategories?: string[];
  facilityTypes?: string[];
  industries?: string[];
  bedCountRange?: { min: number | null; max: number | null };
  hasMaternity?: boolean | null;
  hasOperatingTheatre?: boolean | null;
}

interface ExclusionConfig {
  excludeUnsubscribed: boolean;
  excludeBounced: boolean;
  excludeActiveCampaigns: boolean;
  excludeContactedDays: number | null;
  excludeCampaignIds: string[];
}

interface ActionConfig {
  emailPurpose?: string;
  emailTemplateId?: string;
  leadScoreDelta?: number;
  leadScoreReason?: string;
}

// Recurrence types (Outlook-style)
type RecurrencePattern = 'none' | 'daily' | 'weekly' | 'monthly';
type RecurrenceEndType = 'never' | 'after_count' | 'by_date';

interface RecurrenceConfig {
  interval?: number;
  weekdaysOnly?: boolean;
  daysOfWeek?: number[];
  dayType?: 'dayOfMonth' | 'weekdayOfMonth';
  dayOfMonth?: number;
  weekOfMonth?: number;
  dayOfWeek?: number;
}

interface RecurrenceSettings {
  pattern: RecurrencePattern;
  config: RecurrenceConfig;
  endType: RecurrenceEndType;
  endDate?: string; // ISO date string
  endCount?: number;
}

interface CampaignCreateRequest {
  name: string;
  description?: string;
  targetMode: 'form' | 'natural_language';
  filterConfig?: FilterConfig;
  naturalLanguageQuery?: string;
  exclusionConfig: ExclusionConfig;
  targetSql: string; // Generated SQL from preview step
  targetCount: number;
  targetPreview?: any[]; // Sample contacts from preview
  actionType: 'send_email' | 'update_lead_score' | 'both';
  actionConfig: ActionConfig;
  approvalRequired: boolean;
  scheduledAt?: string; // ISO date string, null for immediate
  sendTime: string; // HH:MM format
  timezone: string;
  dailyLimit: number;
  batchSize: number;
  excludeWeekends: boolean;
  fromMailboxId: string;
  productId?: string;
  recurrence?: RecurrenceSettings; // Outlook-style recurring schedules
}

serve(async (req) => {
  // Handle CORS preflight
  const corsResponse = handleCors(req);
  if (corsResponse) return corsResponse;

  // Only allow POST requests
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get user from auth header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);

    if (authError || !user) {
      return new Response(
        JSON.stringify({ success: false, error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parse request body
    const body: CampaignCreateRequest = await req.json();

    console.log(`[CampaignCreate] Creating campaign: ${body.name} by user ${user.id}`);

    // Validate required fields
    if (!body.name) {
      return new Response(
        JSON.stringify({ success: false, error: "Campaign name is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!body.targetSql) {
      return new Response(
        JSON.stringify({ success: false, error: "Target SQL is required (run preview first)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!body.fromMailboxId) {
      return new Response(
        JSON.stringify({ success: false, error: "From mailbox is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get user's profile ID for created_by
    const { data: profile } = await supabase
      .from('profiles')
      .select('profile_id')
      .eq('profile_id', user.id)
      .single();

    // Determine initial status
    const isImmediate = !body.scheduledAt;
    const initialStatus = isImmediate ? 'running' : 'scheduled';

    // Calculate scheduled_at timestamp
    let scheduledAt: string | null = null;
    if (body.scheduledAt) {
      // Combine date with send time
      const scheduledDate = new Date(body.scheduledAt);
      const [hours, minutes] = body.sendTime.split(':').map(Number);
      scheduledDate.setHours(hours, minutes, 0, 0);
      scheduledAt = scheduledDate.toISOString();
    }

    // Build steps array (single step for now)
    const steps = [{
      step: 1,
      action_type: body.actionType,
      action_config: body.actionConfig,
      delay_days: 0,
    }];

    // Handle recurrence settings
    const recurrence = body.recurrence;
    const isRecurring = recurrence && recurrence.pattern !== 'none';

    // Calculate next_run_at for recurring campaigns
    let nextRunAt: string | null = null;
    if (isRecurring) {
      // For recurring campaigns, next_run_at is the first scheduled run
      if (scheduledAt) {
        nextRunAt = scheduledAt;
      } else {
        // For immediate + recurring, set next_run to now
        nextRunAt = new Date().toISOString();
      }
    }

    // Create campaign_sequences record
    const campaignData: Record<string, any> = {
      name: body.name,
      description: body.description || null,
      target_mode: body.targetMode,
      filter_config: body.filterConfig || {},
      natural_language_query: body.naturalLanguageQuery || null,
      target_sql: body.targetSql,
      target_count: body.targetCount,
      target_preview: body.targetPreview || [],
      exclusion_config: body.exclusionConfig,
      steps: steps,
      action_type: body.actionType,
      action_config: body.actionConfig,
      approval_required: body.approvalRequired,
      from_mailbox_id: body.fromMailboxId,
      product_id: body.productId || null,
      scheduled_at: scheduledAt,
      send_time: body.sendTime,
      timezone: body.timezone,
      daily_limit: body.dailyLimit,
      batch_size: body.batchSize,
      exclude_weekends: body.excludeWeekends,
      status: initialStatus,
      target_locked_at: new Date().toISOString(),
      created_by: profile?.profile_id || null,
      started_at: isImmediate ? new Date().toISOString() : null,
      // Recurrence fields
      recurrence_pattern: recurrence?.pattern || 'none',
      recurrence_config: recurrence?.config || {},
      recurrence_end_type: isRecurring ? (recurrence?.endType || 'never') : null,
      recurrence_end_date: recurrence?.endDate ? new Date(recurrence.endDate).toISOString() : null,
      recurrence_end_count: recurrence?.endCount || null,
      recurrence_count: 0,
      last_run_at: null,
      next_run_at: nextRunAt,
    };

    const { data: campaign, error: createError } = await supabase
      .from('campaign_sequences')
      .insert(campaignData)
      .select()
      .single();

    if (createError) {
      console.error('[CampaignCreate] Error creating campaign:', createError);
      throw new Error(`Failed to create campaign: ${createError.message}`);
    }

    console.log(`[CampaignCreate] Campaign created: ${campaign.id}`);

    // If immediate start, enroll contacts now
    let enrollmentCount = 0;
    if (isImmediate) {
      enrollmentCount = await enrollContacts(supabase, campaign.id, body.targetSql, body.batchSize);
      console.log(`[CampaignCreate] Enrolled ${enrollmentCount} contacts for immediate start`);
    }

    // Build success message
    let successMessage: string;
    if (isRecurring) {
      const patternText = {
        daily: 'daily',
        weekly: 'weekly',
        monthly: 'monthly',
      }[recurrence!.pattern] || '';
      successMessage = isImmediate
        ? `Recurring ${patternText} campaign started! ${enrollmentCount} contacts enrolled for first occurrence.`
        : `Recurring ${patternText} campaign scheduled for ${campaign.scheduled_at}`;
    } else {
      successMessage = isImmediate
        ? `Campaign started! ${enrollmentCount} contacts enrolled.`
        : `Campaign scheduled for ${campaign.scheduled_at}`;
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          campaignId: campaign.id,
          name: campaign.name,
          status: campaign.status,
          targetCount: campaign.target_count,
          enrolledCount: enrollmentCount,
          scheduledAt: campaign.scheduled_at,
          isRecurring: isRecurring,
          recurrencePattern: campaign.recurrence_pattern,
          nextRunAt: campaign.next_run_at,
          message: successMessage,
        },
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );

  } catch (error) {
    console.error("[CampaignCreate] Error:", error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

/**
 * Enroll contacts into the campaign based on target SQL
 */
async function enrollContacts(
  supabase: any,
  campaignId: string,
  targetSql: string,
  batchSize: number
): Promise<number> {
  try {
    // Get target contact IDs
    const { data: previewData, error: previewError } = await supabase
      .rpc('exec_campaign_preview_sql', {
        query: targetSql,
        preview_limit: 10000 // Max contacts to enroll at once
      });

    if (previewError) {
      console.error('[CampaignCreate] Error getting target contacts:', previewError);
      return 0;
    }

    const contacts = previewData?.[0]?.preview_results || [];

    if (contacts.length === 0) {
      console.log('[CampaignCreate] No contacts to enroll');
      return 0;
    }

    // Create enrollment records
    // For immediate campaigns, set next_send_date to now
    // For scheduled, the campaign-executor will set it based on schedule
    const now = new Date().toISOString();

    const enrollments = contacts.map((contact: any, index: number) => ({
      campaign_sequence_id: campaignId,
      contact_id: contact.contact_id || contact.id,
      current_step: 1,
      status: 'enrolled',
      next_send_date: now, // Ready to process immediately
      enrolled_by: 'campaign_create',
      enrolled_at: now,
    }));

    // Insert in batches to avoid overwhelming the database
    const BATCH_SIZE = 500;
    let totalInserted = 0;

    for (let i = 0; i < enrollments.length; i += BATCH_SIZE) {
      const batch = enrollments.slice(i, i + BATCH_SIZE);

      const { error: insertError } = await supabase
        .from('campaign_enrollments')
        .insert(batch)
        .select();

      if (insertError) {
        // Handle unique constraint violations (contact already enrolled)
        if (insertError.code === '23505') {
          console.warn('[CampaignCreate] Some contacts already enrolled, skipping duplicates');
          // Try individual inserts to get as many as possible
          for (const enrollment of batch) {
            const { error: singleError } = await supabase
              .from('campaign_enrollments')
              .insert(enrollment);

            if (!singleError) {
              totalInserted++;
            }
          }
        } else {
          console.error('[CampaignCreate] Error inserting enrollments:', insertError);
        }
      } else {
        totalInserted += batch.length;
      }
    }

    // Update campaign with actual enrolled count
    await supabase
      .from('campaign_sequences')
      .update({ target_count: totalInserted })
      .eq('id', campaignId);

    return totalInserted;

  } catch (error) {
    console.error('[CampaignCreate] Error enrolling contacts:', error);
    return 0;
  }
}
