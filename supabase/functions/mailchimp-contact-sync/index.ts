import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';
import {
  completeSyncRun,
  createSyncRun,
  exportMailchimpContacts,
  fetchMailchimpAudiences,
  importMailchimpContacts,
  storeMailchimpAudiences,
} from '../_shared/mailchimp-contacts.ts';

type Action = 'import' | 'export' | 'sync';

const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

function isServiceRoleRequest(req: Request): boolean {
  const authHeader = req.headers.get('authorization') ?? '';
  return authHeader.startsWith('Bearer ') && authHeader.replace('Bearer ', '') === SERVICE_ROLE_KEY;
}

function isAction(value: unknown): value is Action {
  return value === 'import' || value === 'export' || value === 'sync';
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

  try {
    const body = req.method === 'POST' ? await req.json().catch(() => ({})) : {};
    if (!isAction(body?.action)) {
      return new Response(JSON.stringify({ error: 'action must be import, export, or sync' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const listId = String(body?.list_id ?? '').trim();
    if (!listId) {
      return new Response(JSON.stringify({ error: 'list_id is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const dryRun = Boolean(body?.dry_run ?? true);
    const limit = Number.isFinite(Number(body?.limit)) ? Number(body.limit) : undefined;
    const offset = Number.isFinite(Number(body?.offset)) ? Number(body.offset) : undefined;

    const audiences = await fetchMailchimpAudiences();
    await storeMailchimpAudiences(supabase, audiences);

    runId = await createSyncRun(supabase, {
      action: body.action,
      listId,
      requestedBy: auth.user?.id,
      dryRun,
    });

    const stats = body.action === 'import'
      ? { import: await importMailchimpContacts(supabase, { listId, limit, offset, dryRun }) }
      : body.action === 'export'
        ? { export: await exportMailchimpContacts(supabase, { listId, limit, dryRun }) }
        : {
          import: await importMailchimpContacts(supabase, { listId, limit, offset, dryRun }),
          export: await exportMailchimpContacts(supabase, { listId, limit, dryRun }),
        };

    await completeSyncRun(supabase, runId, 'completed', stats);

    return new Response(JSON.stringify({
      ok: true,
      action: body.action,
      list_id: listId,
      dry_run: dryRun,
      offset,
      run_id: runId,
      stats,
      completed_at: new Date().toISOString(),
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('[MailchimpContactSync] Error:', error);
    const message = error instanceof Error ? error.message : 'Unknown Mailchimp contact sync error';
    await completeSyncRun(supabase, runId, 'failed', {}, message);
    return new Response(JSON.stringify({ ok: false, error: message, run_id: runId }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
