/**
 * GET /email-sync-processes
 *
 * Returns last/next-run + outcome for each background process powering
 * the email pipeline. Drives the "Background processes" section of the
 * settings -> mailbox page.
 *
 * Output shape:
 *   {
 *     processes: [
 *       {
 *         id, name, description,
 *         status: 'active' | 'error' | 'disabled',
 *         enabled: bool,
 *         last_run_at: iso | null,
 *         last_outcome: string | null,
 *         next_run_at: iso | null,
 *         schedule_minutes: number
 *       }
 *     ]
 *   }
 */
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

interface ProcessSpec {
  id: string;
  name: string;
  description: string;
  process_key: string;       // value of email_sync_run_log.process
  schedule_minutes: number;  // cadence
  config_enabled_key?: string; // optional system_config row controlling on/off
}

const PROCESSES: ProcessSpec[] = [
  {
    id: "sync",
    name: "Scheduled sync",
    description: "Pulls new emails from all mailboxes",
    process_key: "sync",
    schedule_minutes: 5,
    config_enabled_key: "email_sync_enabled",
  },
  {
    id: "retry",
    name: "Retry failed imports",
    description: "Tries again on transient errors",
    process_key: "retry_errors",
    schedule_minutes: 30,
  },
  {
    id: "enrich",
    name: "AI enrichment backfill",
    description: "Catches up emails imported in bulk",
    process_key: "enrich_pending",
    schedule_minutes: 10,
    config_enabled_key: "enrichment_enabled",
  },
  {
    id: "watchdog",
    name: "Stuck-job watchdog",
    description: "Detects and recovers stuck imports",
    process_key: "watchdog",
    schedule_minutes: 5,
  },
  {
    id: "auto_report",
    name: "Auto-report failures",
    description: "Files GitHub issues for recurring import errors",
    process_key: "auto_report_failures",
    schedule_minutes: 15,
  },
];

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

    // Pull all enabled-flag config rows in one round-trip.
    const enabledKeys = PROCESSES
      .map((p) => p.config_enabled_key)
      .filter((k): k is string => typeof k === "string");

    const { data: configRows } = await supabase
      .from("system_config")
      .select("key,value")
      .in("key", enabledKeys);

    // deno-lint-ignore no-explicit-any
    const configMap = new Map<string, any>(
      (configRows ?? []).map((r: { key: string; value: unknown }) => [
        r.key,
        r.value,
      ]),
    );

    const processes = await Promise.all(PROCESSES.map(async (p) => {
      const { data: lastRows } = await supabase
        .from("email_sync_run_log")
        .select("started_at,completed_at,outcome")
        .eq("process", p.process_key)
        .order("started_at", { ascending: false })
        .limit(1);

      const last = lastRows?.[0];
      const lastRunAt: string | null = last?.completed_at ?? last?.started_at ??
        null;
      const lastOutcome: string | null = last?.outcome ?? null;

      let enabled = true;
      if (p.config_enabled_key) {
        const v = configMap.get(p.config_enabled_key);
        // Treat both boolean false and string "false" as disabled.
        // Missing config row => enabled (default-on).
        enabled = !(v === false || v === "false");
      }

      // Compute next_run_at from last_run_at + schedule_minutes when enabled.
      // If nothing has run yet OR the process is disabled, leave next_run_at null.
      let nextRunAt: string | null = null;
      if (lastRunAt && enabled) {
        nextRunAt = new Date(
          new Date(lastRunAt).getTime() + p.schedule_minutes * 60_000,
        ).toISOString();
      }

      let status: "active" | "error" | "disabled";
      if (!enabled) {
        status = "disabled";
      } else if (typeof lastOutcome === "string" && lastOutcome.startsWith("Failed")) {
        status = "error";
      } else {
        status = "active";
      }

      return {
        id: p.id,
        name: p.name,
        description: p.description,
        enabled,
        status,
        last_run_at: lastRunAt,
        last_outcome: lastOutcome,
        next_run_at: nextRunAt,
        schedule_minutes: p.schedule_minutes,
      };
    }));

    return new Response(
      JSON.stringify({ processes }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err) {
    console.error("email-sync-processes error:", err);
    return new Response(
      JSON.stringify({
        error: "Failed to compute processes",
        message: err instanceof Error ? err.message : String(err),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
