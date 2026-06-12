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
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';

function isServiceRoleRequest(req: Request): boolean {
  const authHeader = req.headers.get('authorization') ?? '';
  return authHeader.startsWith('Bearer ') && authHeader.replace('Bearer ', '') === SERVICE_ROLE_KEY;
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const [, payload] = token.split('.');
  if (!payload) return null;

  try {
    return JSON.parse(atob(payload.replace(/-/g, '+').replace(/_/g, '/')));
  } catch {
    return null;
  }
}

function projectRefFromUrl(url: string): string | null {
  try {
    return new URL(url).hostname.split('.')[0] || null;
  } catch {
    return null;
  }
}

async function isValidServiceRoleJwtRequest(req: Request): Promise<boolean> {
  const authHeader = req.headers.get('authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return false;

  const token = authHeader.replace('Bearer ', '').trim();
  const payload = decodeJwtPayload(token);
  if (payload?.role !== 'service_role') return false;

  const projectRef = projectRefFromUrl(SUPABASE_URL);
  if (projectRef && payload.ref && payload.ref !== projectRef) return false;

  const response = await fetch(`${SUPABASE_URL}/rest/v1/profiles?select=auth_user_id&limit=1`, {
    headers: {
      apikey: token,
      Authorization: `Bearer ${token}`,
    },
  });

  return response.ok;
}

function isAction(value: unknown): value is Action {
  return value === 'import' || value === 'export' || value === 'sync';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  const auth = isServiceRoleRequest(req) || await isValidServiceRoleJwtRequest(req)
    ? { user: { id: 'service-role' } }
    : await requireAdmin(req);
  if (auth instanceof Response) return auth;

  const supabase = createClient(
    SUPABASE_URL,
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
