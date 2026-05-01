/**
 * GET /email-sync-health
 *
 * Returns the aggregated health state for the in-app banner stack and
 * sidebar badge. Replaces the CloudWatch-alarm-only model — UI polls
 * this endpoint and renders zero or more banner items.
 *
 * Output shape:
 *   {
 *     state: 'healthy' | 'yellow' | 'red',
 *     items: [
 *       { severity, title, description, action_label?, action_url? }
 *     ],
 *     counts: { red: N, yellow: M }
 *   }
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

interface HealthItem {
  severity: "red" | "yellow";
  title: string;
  description: string;
  action_label?: string;
  action_url?: string;
}

// deno-lint-ignore no-explicit-any
async function buildItems(supabase: any): Promise<HealthItem[]> {
  const items: HealthItem[] = [];

  // 1. Unresolved import errors -> red
  const { count: errCount } = await supabase
    .from("email_import_errors")
    .select("id", { count: "exact", head: true })
    .is("resolved_at", null);
  if (errCount && errCount > 0) {
    items.push({
      severity: "red",
      title: `${errCount} email${errCount === 1 ? "" : "s"} couldn't be imported`,
      description:
        "Some are transient errors that can be retried; others need the dev team.",
      action_label: "Review",
      action_url: "/settings/mailbox#failures",
    });
  }

  // 2. Stuck-job-watchdog reset events in last hour -> yellow
  // The watchdog logs a run with emails_processed > 0 when it resets a stuck job.
  const oneHourAgoIso = new Date(Date.now() - 3600_000).toISOString();
  const { data: watchdogResets } = await supabase
    .from("email_sync_run_log")
    .select("outcome,started_at")
    .eq("process", "watchdog")
    .gt("emails_processed", 0)
    .gte("started_at", oneHourAgoIso)
    .limit(1);
  if (watchdogResets && watchdogResets.length > 0) {
    items.push({
      severity: "yellow",
      title: "A stuck import was reset",
      description:
        "An import job stopped responding and was marked failed. Review and retry.",
      action_label: "Review",
      action_url: "/settings/mailbox",
    });
  }

  // 3. AI enrichment 429 / error rate > 5% over last hour -> yellow
  const { data: enrichLogs } = await supabase
    .from("ai_enrichment_logs")
    .select("success_count,error_count")
    .gte("created_at", oneHourAgoIso);
  if (enrichLogs && enrichLogs.length > 0) {
    let total = 0;
    let errors = 0;
    for (const r of enrichLogs) {
      total += (r.success_count ?? 0) + (r.error_count ?? 0);
      errors += r.error_count ?? 0;
    }
    if (total > 20 && errors / total > 0.05) {
      items.push({
        severity: "yellow",
        title: "AI provider is rate-limiting us",
        description:
          "New emails are still being imported, but AI enrichment is paused for ~15 minutes. We will resume automatically.",
      });
    }
  }

  // 4. Pending-enrichment backlog older than 24h -> yellow
  const oneDayAgoIso = new Date(Date.now() - 86400_000).toISOString();
  const { count: pendingCount } = await supabase
    .from("emails")
    .select("id", { count: "exact", head: true })
    .eq("enrichment_status", "pending")
    .lt("created_at", oneDayAgoIso);
  if (pendingCount && pendingCount > 500) {
    items.push({
      severity: "yellow",
      title: `${pendingCount.toLocaleString()} emails are awaiting AI enrichment`,
      description: "They will catch up automatically over the next few hours.",
    });
  }

  return items;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;

  try {
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
    const items = await buildItems(supabase);
    const counts = {
      red: items.filter((i) => i.severity === "red").length,
      yellow: items.filter((i) => i.severity === "yellow").length,
    };
    const state: "red" | "yellow" | "healthy" = counts.red > 0
      ? "red"
      : counts.yellow > 0
      ? "yellow"
      : "healthy";

    return new Response(
      JSON.stringify({ state, items, counts }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("email-sync-health error:", err);
    return new Response(
      JSON.stringify({
        error: "Failed to compute health",
        message: err instanceof Error ? err.message : String(err),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
