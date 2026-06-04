import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';
import { getExportPreview } from '../_shared/mailchimp-contacts.ts';

const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

function isServiceRoleRequest(req: Request): boolean {
  const authHeader = req.headers.get('authorization') ?? '';
  return authHeader.startsWith('Bearer ') && authHeader.replace('Bearer ', '') === SERVICE_ROLE_KEY;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  if (!isServiceRoleRequest(req)) {
    const auth = await requireAdmin(req);
    if (auth instanceof Response) return auth;
  }

  try {
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    const listId = String(body?.list_id ?? '').trim();
    if (!listId) {
      return new Response(JSON.stringify({ error: 'list_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    );
    const preview = await getExportPreview(supabase, listId);

    return new Response(JSON.stringify({ ok: true, preview }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('[MailchimpContactExportPreview] Error:', error);
    const message = error instanceof Error ? error.message : 'Unknown preview error';
    return new Response(JSON.stringify({ ok: false, error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
