import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';
import {
  MailchimpEngagementStats,
  MailchimpNewsletterForEngagement,
  syncMailchimpEngagementForNewsletters,
} from '../_shared/mailchimp-engagement.ts';

interface SyncRequest {
  campaign_id?: string;
  lookback_days?: number;
  limit?: number;
  source?: 'manual_ui' | 'pg_cron' | 'manual' | string;
  dry_run?: boolean;
}

interface EngagementConfig {
  enabled: boolean;
  lookbackDays: number;
  campaignLimit: number;
}

const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

function isServiceRoleRequest(req: Request): boolean {
  const authHeader = req.headers.get('authorization') ?? '';
  return authHeader.startsWith('Bearer ') && authHeader.replace('Bearer ', '') === SERVICE_ROLE_KEY;
}

function emptyStats(): MailchimpEngagementStats {
  return {
    campaigns_scanned: 0,
    activities_scanned: 0,
    events_inserted: 0,
    events_skipped_existing: 0,
    contacts_matched: 0,
    contacts_missing: 0,
    summaries_updated: 0,
    errors: [],
  };
}

async function getMailchimpEngagementConfig(supabase: any): Promise<EngagementConfig> {
  const { data, error } = await supabase
    .from('system_config')
    .select('key, value')
    .in('key', [
      'mailchimp_engagement_sync_enabled',
      'mailchimp_engagement_sync_lookback_days',
      'mailchimp_engagement_sync_campaign_limit',
    ]);

  if (error) throw new Error(`Failed to load Mailchimp engagement sync settings: ${error.message}`);

  const rows = (data ?? []) as Array<{ key: string; value: unknown }>;
  const config = new Map(rows.map((row) => [row.key, row.value]));

  return {
    enabled: Boolean(config.get('mailchimp_engagement_sync_enabled') ?? true),
    lookbackDays: Number(config.get('mailchimp_engagement_sync_lookback_days') ?? 7),
    campaignLimit: Number(config.get('mailchimp_engagement_sync_campaign_limit') ?? 25),
  };
}

async function createEngagementRun(
  supabase: any,
  input: {
    source: string;
    requestedBy?: string | null;
    campaignId?: string | null;
    dryRun: boolean;
  },
): Promise<string | null> {
  const requestedBy = input.requestedBy && input.requestedBy !== 'service-role'
    ? input.requestedBy
    : null;

  const { data, error } = await supabase
    .from('mailchimp_engagement_sync_runs')
    .insert({
      source: input.source,
      status: 'running',
      requested_by: requestedBy,
      campaign_id: input.campaignId ?? null,
      dry_run: input.dryRun,
    })
    .select('id')
    .single();

  if (error) {
    console.warn('[SyncMailchimpEngagement] Failed to create run record:', error);
    return null;
  }

  return data?.id ?? null;
}

async function completeEngagementRun(
  supabase: any,
  runId: string | null,
  status: 'completed' | 'failed',
  stats: MailchimpEngagementStats,
  error?: string | null,
): Promise<void> {
  if (!runId) return;

  const { error: updateError } = await supabase
    .from('mailchimp_engagement_sync_runs')
    .update({
      status,
      stats,
      error: error ?? null,
      completed_at: new Date().toISOString(),
    })
    .eq('id', runId);

  if (updateError) {
    console.warn('[SyncMailchimpEngagement] Failed to complete run record:', updateError);
  }
}

async function loadNewsletterByCampaignId(
  supabase: any,
  campaignId: string,
): Promise<MailchimpNewsletterForEngagement[]> {
  const { data, error } = await supabase
    .from('mailchimp_newsletters')
    .select('id, mailchimp_campaign_id, campaign_id, title, subject, audience_id, sent_at')
    .eq('mailchimp_campaign_id', campaignId)
    .maybeSingle();

  if (error) throw new Error(`Failed to load Mailchimp newsletter ${campaignId}: ${error.message}`);
  if (!data) throw new Error(`Mailchimp newsletter ${campaignId} has not been synced locally`);
  return [data as MailchimpNewsletterForEngagement];
}

async function loadRecentNewsletters(
  supabase: any,
  lookbackDays: number,
  limit: number,
): Promise<MailchimpNewsletterForEngagement[]> {
  const sentSince = new Date(Date.now() - (lookbackDays * 24 * 60 * 60 * 1000)).toISOString();
  const { data, error } = await supabase
    .from('mailchimp_newsletters')
    .select('id, mailchimp_campaign_id, campaign_id, title, subject, audience_id, sent_at')
    .gte('sent_at', sentSince)
    .order('sent_at', { ascending: false })
    .limit(limit);

  if (error) throw new Error(`Failed to load recent Mailchimp newsletters: ${error.message}`);
  return (data ?? []) as MailchimpNewsletterForEngagement[];
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  const auth = isServiceRoleRequest(req) ? { user: { id: 'service-role' } } : await requireAdmin(req);
  if (auth instanceof Response) return auth;

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  let runId: string | null = null;
  let stats = emptyStats();

  try {
    const body: SyncRequest = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    const source = body.source ?? 'manual';
    const dryRun = Boolean(body.dry_run);
    const config = await getMailchimpEngagementConfig(supabase);

    if (source === 'pg_cron' && !config.enabled) {
      return new Response(JSON.stringify({
        ok: true,
        skipped: true,
        ...stats,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const campaignId = body.campaign_id?.trim() || null;
    runId = await createEngagementRun(supabase, {
      source,
      requestedBy: auth.user?.id,
      campaignId,
      dryRun,
    });

    const lookbackDays = Math.max(1, Math.min(Number(body.lookback_days ?? config.lookbackDays), 365));
    const limit = Math.max(1, Math.min(Number(body.limit ?? config.campaignLimit), 100));
    const newsletters = campaignId
      ? await loadNewsletterByCampaignId(supabase, campaignId)
      : await loadRecentNewsletters(supabase, lookbackDays, limit);

    stats = await syncMailchimpEngagementForNewsletters(supabase, newsletters, {
      dryRun,
    });

    await completeEngagementRun(supabase, runId, 'completed', stats);

    return new Response(JSON.stringify({
      ok: true,
      skipped: false,
      dry_run: dryRun,
      lookback_days: lookbackDays,
      limit,
      run_id: runId,
      ...stats,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('[SyncMailchimpEngagement] Error:', error);
    const message = error instanceof Error ? error.message : 'Unknown Mailchimp engagement sync error';
    await completeEngagementRun(supabase, runId, 'failed', stats, message);
    return new Response(JSON.stringify({
      ok: false,
      error: message,
      run_id: runId,
      ...stats,
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
