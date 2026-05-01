/**
 * POST /report-import-failure-to-github
 * Body: { failure_group_id: string }
 *
 * Creates a GitHub issue for the failure group if not already created;
 * stores github_issue_url and _number on the group; idempotent.
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { corsHeaders } from "../_shared/cors.ts";
import { createIssue } from "../_shared/github.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: corsHeaders });

  const { failure_group_id } = await req.json();
  if (!failure_group_id) return new Response(JSON.stringify({ error: 'failure_group_id required' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  // deno-lint-ignore no-explicit-any
  const supabase: any = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: group, error: groupErr } = await supabase
    .from('email_import_failure_groups')
    .select('*')
    .eq('id', failure_group_id)
    .single();
  if (groupErr || !group) return new Response(JSON.stringify({ error: 'group not found' }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

  if (group.github_issue_url) {
    return new Response(JSON.stringify({ ok: true, already_reported: true, url: group.github_issue_url, number: group.github_issue_number }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }

  // Sample 3 recent example errors for the issue body
  const { data: examples } = await supabase
    .from('email_import_errors')
    .select('mailbox_id,imap_folder,imap_uid,error_message,created_at')
    .eq('failure_group_id', failure_group_id)
    .order('created_at', { ascending: false })
    .limit(3);

  // deno-lint-ignore no-explicit-any
  const exampleBlock = ((examples ?? []) as any[]).map((e, i) => (
    `### Example ${i+1}\n- Mailbox: ${e.mailbox_id}\n- Folder: ${e.imap_folder}\n- IMAP UID: ${e.imap_uid}\n- Time: ${e.created_at}\n- Error: \`${(e.error_message ?? '').slice(0, 200)}\``
  )).join('\n\n');

  const title = `Email import failure: ${(group.error_pattern ?? '').slice(0, 80)}`;
  const body = `**Auto-reported from production.** This is a recurring import failure that has happened ${group.occurrence_count} times since ${group.first_seen_at}.

**Error signature:** \`${group.error_signature}\`
**First seen:** ${group.first_seen_at}
**Last seen:** ${group.last_seen_at}
**Occurrences:** ${group.occurrence_count}

## Examples

${exampleBlock || '_(none)_'}

---
_Reported by \`report-import-failure-to-github\` edge function. Mark this issue closed to clear the in-app banner; the system will reopen it if the same signature recurs._`;

  const result = await createIssue({ title, body, labels: ['email-sync-bug', 'auto-reported'] });

  await supabase
    .from('email_import_failure_groups')
    .update({ github_issue_url: result.html_url, github_issue_number: result.number })
    .eq('id', failure_group_id);

  return new Response(JSON.stringify({ ok: true, url: result.html_url, number: result.number }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
});
