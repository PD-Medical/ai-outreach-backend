/**
 * GET /email-sync-activity?mailbox_id=&status=&from=&to=&q=&cursor=&limit=50
 *
 * Returns a paginated activity log:
 *   { rows: [...v_email_activity rows], next_cursor: string|null, total_estimate: number|null }
 *
 * Cursor format: ISO timestamp of `imported_at` of the last row in the previous page.
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const url = new URL(req.url);
  const mailboxId = url.searchParams.get('mailbox_id');
  const status = url.searchParams.get('status'); // pending|enriched|failed|rate_limited|skipped|all
  const from = url.searchParams.get('from');
  const to = url.searchParams.get('to');
  const q = url.searchParams.get('q')?.trim() || '';
  const cursor = url.searchParams.get('cursor');
  const limit = Math.min(parseInt(url.searchParams.get('limit') ?? '50', 10), 200);

  // deno-lint-ignore no-explicit-any
  const supabase: any = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  let query = supabase
    .from('v_email_activity')
    .select('*')
    .order('imported_at', { ascending: false })
    .limit(limit + 1);

  if (mailboxId) query = query.eq('mailbox_id', mailboxId);
  if (status && status !== 'all') query = query.eq('enrichment_status', status);
  if (from) query = query.gte('imported_at', from);
  if (to) query = query.lte('imported_at', to);
  if (q) query = query.or(
    `from_address.ilike.%${q}%,from_name.ilike.%${q}%,subject.ilike.%${q}%,message_id.ilike.%${q}%`
  );
  if (cursor) query = query.lt('imported_at', cursor);

  const { data, error } = await query;
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  const rows = data ?? [];
  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  const nextCursor = hasMore ? page[page.length - 1].imported_at : null;

  // Approximate total via head count, only on the first page (no cursor) to save cost on subsequent pages.
  let totalEstimate: number | null = null;
  if (!cursor) {
    let countQ = supabase.from('v_email_activity').select('id', { count: 'exact', head: true });
    if (mailboxId) countQ = countQ.eq('mailbox_id', mailboxId);
    if (status && status !== 'all') countQ = countQ.eq('enrichment_status', status);
    if (from) countQ = countQ.gte('imported_at', from);
    if (to) countQ = countQ.lte('imported_at', to);
    const { count } = await countQ;
    totalEstimate = count ?? null;
  }

  return new Response(JSON.stringify({ rows: page, next_cursor: nextCursor, total_estimate: totalEstimate }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
});
