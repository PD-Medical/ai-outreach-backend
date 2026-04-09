import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';
import {
  logMailchimpNewsletterEvent,
  syncMailchimpCampaignToDb,
  syncRecentMailchimpCampaignsToDb,
} from '../_shared/mailchimp-newsletters.ts';

interface SyncRequest {
  campaign_id?: string;
  sent_since?: string;
  lookback_days?: number;
  limit?: number;
  source?: string;
}

const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

function isServiceRoleRequest(req: Request): boolean {
  const authHeader = req.headers.get('authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return false;
  return authHeader.replace('Bearer ', '') === SERVICE_ROLE_KEY;
}

async function getMailchimpSyncConfig(supabase: any) {
  const { data, error } = await supabase
    .from('system_config')
    .select('key, value')
    .in('key', [
      'mailchimp_newsletter_sync_lookback_days',
      'mailchimp_newsletter_sync_limit',
    ]);

  if (error) {
    throw new Error(`Failed to load Mailchimp sync settings: ${error.message}`);
  }

  const rows = (data ?? []) as Array<{ key: string; value: unknown }>;
  const configMap = new Map(rows.map((row) => [row.key, row.value]));
  return {
    lookbackDays: Number(configMap.get('mailchimp_newsletter_sync_lookback_days') ?? 30),
    limit: Number(configMap.get('mailchimp_newsletter_sync_limit') ?? 25),
  };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  if (!isServiceRoleRequest(req)) {
    const auth = await requireAdmin(req);
    if (auth instanceof Response) return auth;
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  try {
    const body: SyncRequest = req.method === 'POST' ? await req.json() : {};
    const config = await getMailchimpSyncConfig(supabase);

    if (body.campaign_id) {
      const newsletter = await syncMailchimpCampaignToDb(supabase, body.campaign_id);
      await logMailchimpNewsletterEvent(supabase, {
        source: body.source ?? 'manual',
        campaign_id: body.campaign_id,
      }, {
        eventType: body.source === 'pg_cron' ? 'scheduled_campaign_sync' : 'manual_campaign_sync',
        campaignId: body.campaign_id,
        processingStatus: 'processed',
        processedAt: new Date().toISOString(),
      });

      return new Response(JSON.stringify({
        ok: true,
        synced: 1,
        newsletters: [newsletter],
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const lookbackDays = Math.max(1, body.lookback_days ?? config.lookbackDays);
    const sentSince = body.sent_since ?? new Date(Date.now() - (lookbackDays * 24 * 60 * 60 * 1000)).toISOString();
    const limit = Math.max(1, body.limit ?? config.limit);

    const newsletters = await syncRecentMailchimpCampaignsToDb(supabase, {
      sentSince,
      limit,
    });

    await logMailchimpNewsletterEvent(supabase, {
      source: body.source ?? 'manual',
      sent_since: sentSince,
      lookback_days: lookbackDays,
      limit,
      synced: newsletters.length,
    }, {
      eventType: body.source === 'pg_cron' ? 'scheduled_sync' : 'manual_sync',
      processingStatus: 'processed',
      processedAt: new Date().toISOString(),
    });

    return new Response(JSON.stringify({
      ok: true,
      sent_since: sentSince,
      lookback_days: lookbackDays,
      limit,
      synced: newsletters.length,
      newsletters,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('[SyncMailchimpNewsletters] Error:', error);
    const message = error instanceof Error ? error.message : 'Unknown sync error';
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
