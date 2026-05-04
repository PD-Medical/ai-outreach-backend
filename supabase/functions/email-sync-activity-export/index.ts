/**
 * GET /email-sync-activity-export — same query params as activity, streams CSV.
 * Hard cap: 50,000 rows.
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CSV_HEADER = ['imported_at', 'from_address', 'subject', 'mailbox_email', 'imap_folder', 'enrichment_status', 'enriched_at'].join(',') + '\n';

function csvEscape(v: unknown): string {
  if (v === null || v === undefined) return '';
  const s = String(v);
  if (s.includes(',') || s.includes('"') || s.includes('\n')) return `"${s.replaceAll('"', '""')}"`;
  return s;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;

  const url = new URL(req.url);
  const mailboxId = url.searchParams.get('mailbox_id');
  const status = url.searchParams.get('status');
  const from = url.searchParams.get('from');
  const to = url.searchParams.get('to');
  // deno-lint-ignore no-explicit-any
  const supabase: any = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const stream = new ReadableStream({
    async start(controller) {
      const enc = new TextEncoder();
      controller.enqueue(enc.encode(CSV_HEADER));

      const PAGE = 1000;
      const MAX = 50_000;
      let cursor: string | null = null;
      let written = 0;

      while (written < MAX) {
        let q = supabase
          .from('v_email_activity')
          .select('imported_at, from_address, subject, mailbox_email, imap_folder, enrichment_status, enriched_at')
          .order('imported_at', { ascending: false })
          .limit(PAGE);
        if (mailboxId) q = q.eq('mailbox_id', mailboxId);
        if (status && status !== 'all') q = q.eq('enrichment_status', status);
        if (from) q = q.gte('imported_at', from);
        if (to) q = q.lte('imported_at', to);
        if (cursor) q = q.lt('imported_at', cursor);
        const { data, error } = await q;
        if (error || !data || data.length === 0) break;
        for (const r of data) {
          const line = [r.imported_at, r.from_address, r.subject, r.mailbox_email, r.imap_folder, r.enrichment_status, r.enriched_at].map(csvEscape).join(',') + '\n';
          controller.enqueue(enc.encode(line));
          written++;
        }
        cursor = data[data.length - 1].imported_at;
        if (data.length < PAGE) break;
      }
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      ...corsHeaders,
      'Content-Type': 'text/csv',
      'Content-Disposition': `attachment; filename="email-activity-${new Date().toISOString().slice(0,10)}.csv"`,
    },
  });
});
