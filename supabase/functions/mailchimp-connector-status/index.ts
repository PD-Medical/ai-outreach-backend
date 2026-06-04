import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';
import {
  fetchMailchimpAudiences,
  storeMailchimpAudiences,
} from '../_shared/mailchimp-contacts.ts';

const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

function isServiceRoleRequest(req: Request): boolean {
  const authHeader = req.headers.get('authorization') ?? '';
  return authHeader.startsWith('Bearer ') && authHeader.replace('Bearer ', '') === SERVICE_ROLE_KEY;
}

async function loadConfig(supabase: any) {
  const { data, error } = await supabase
    .from('system_config')
    .select('key, value')
    .in('key', [
      'mailchimp_default_audience_id',
      'mailchimp_contact_sync_tag_prefix',
      'mailchimp_contact_sync_enabled',
    ]);

  if (error) throw new Error(`Failed to load Mailchimp config: ${error.message}`);
  const map = new Map((data ?? []).map((row: { key: string; value: unknown }) => [row.key, row.value]));
  return {
    default_audience_id: map.get('mailchimp_default_audience_id') ?? null,
    tag_prefix: String(map.get('mailchimp_contact_sync_tag_prefix') ?? 'mc:'),
    enabled: Boolean(map.get('mailchimp_contact_sync_enabled') ?? true),
  };
}

async function setDefaultAudience(supabase: any, listId: string | null) {
  const { error } = await supabase
    .from('system_config')
    .upsert({
      key: 'mailchimp_default_audience_id',
      value: listId,
      description: 'Default Mailchimp audience/list ID for contact export and sync.',
    }, { onConflict: 'key' });

  if (error) throw new Error(`Failed to set default audience: ${error.message}`);
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
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    if (body?.default_audience_id !== undefined) {
      await setDefaultAudience(supabase, body.default_audience_id || null);
    }

    const audiences = await fetchMailchimpAudiences();
    await storeMailchimpAudiences(supabase, audiences);
    const config = await loadConfig(supabase);

    return new Response(JSON.stringify({
      ok: true,
      connected: true,
      audiences: audiences.map((audience) => ({
        list_id: audience.id,
        name: audience.name,
        member_count: audience.stats?.member_count ?? null,
        unsubscribe_count: audience.stats?.unsubscribe_count ?? null,
        cleaned_count: audience.stats?.cleaned_count ?? null,
        default_from_name: audience.campaign_defaults?.from_name ?? null,
        default_reply_to_email: audience.campaign_defaults?.from_email?.toLowerCase() ?? null,
      })),
      config,
      checked_at: new Date().toISOString(),
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('[MailchimpConnectorStatus] Error:', error);
    const message = error instanceof Error ? error.message : 'Unknown Mailchimp status error';
    return new Response(JSON.stringify({
      ok: false,
      connected: false,
      error: message,
      checked_at: new Date().toISOString(),
    }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
