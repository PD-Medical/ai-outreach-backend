/**
 * POST /email-import-failure-action
 * Body: { action: 'retry' | 'skip', error_id: string }
 *
 * Retry: re-enqueue a single SQS message for that email's IMAP UID;
 *        on success, the next sync will pick it up and the error will resolve.
 * Skip: set resolved_at on the error row without retrying.
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAdmin } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// deno-lint-ignore no-explicit-any
async function getLambdaUrl(supabase: any): Promise<string> {
  const { data } = await supabase.from('system_config').select('value').eq('key', 'email_sync_url').single();
  if (!data?.value) throw new Error('email_sync_url not configured');
  return data.value as string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'POST required' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  const auth = await requireAdmin(req);
  if (auth instanceof Response) return auth;

  const { action, error_id } = await req.json();
  if (!['retry', 'skip'].includes(action) || !error_id) {
    return new Response(JSON.stringify({ error: 'invalid body' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  // deno-lint-ignore no-explicit-any
  const supabase: any = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: err, error: errFetchErr } = await supabase
    .from('email_import_errors')
    .select('id,mailbox_id,imap_folder,imap_uid,error_class,resolved_at')
    .eq('id', error_id)
    .single();
  if (errFetchErr || !err) {
    return new Response(JSON.stringify({ error: 'error not found' }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  if (err.resolved_at) {
    return new Response(JSON.stringify({ ok: true, already_resolved: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  if (action === 'skip') {
    await supabase.from('email_import_errors').update({ resolved_at: new Date().toISOString() }).eq('id', error_id);
    return new Response(JSON.stringify({ ok: true, action: 'skipped' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  // Retry: only allow on transient errors
  if (err.error_class === 'persistent') {
    return new Response(JSON.stringify({ error: 'cannot retry a persistent error' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  const lambdaUrl = await getLambdaUrl(supabase);
  const resp = await fetch(lambdaUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ mode: 'retry_errors', error_ids: [error_id] }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    return new Response(JSON.stringify({ error: 'lambda invoke failed', detail: text }), { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
  return new Response(JSON.stringify({ ok: true, action: 'retried' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
});
