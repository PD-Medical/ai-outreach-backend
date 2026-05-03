/**
 * Contacts Export Edge Function (Train G)
 *
 * Builds a CSV of contacts and returns it as a JSON envelope so the frontend
 * can trigger a browser download.
 *
 * Request body:
 *   {
 *     format: 'csv',                  // only csv for v1
 *     fields: string[],               // whitelist below; defaults if omitted
 *     contact_ids?: string[],         // optional filter; if absent, ALL contacts
 *     limit?: number,                 // safety cap (default 5000, max 10000)
 *   }
 *
 * Response shape:
 *   {
 *     success: true,
 *     filename: 'contacts-2026-05-02.csv',
 *     mime: 'text/csv',
 *     content: '<csv text>',
 *     rows: 1234,
 *   }
 *
 * Source: v_contact_engagement_profile view — has org names + stats already
 * joined, so no extra round-trips needed. engagement_summary fields come
 * through as cached values; null cells when not yet generated (operators can
 * trigger generation by opening the contact's modal).
 *
 * Auth: requireAdmin. Bulk contact export contains PII (email, phone, notes,
 * AI summaries) — restricting to admin role matches the principle of least
 * privilege. The user-facing app (Contacts page Export button) is admin-only
 * for this reason.
 *
 * Why no storage / signed URL: keeping v1 sync + JSON-text means no Storage
 * bucket setup, no retention policy, no async polling UI. CSV files for
 * 1000 contacts × 20 fields ≈ 200KB — fits comfortably in a JSON response.
 * Excel format + async path are deferred until a real volume need shows up.
 *
 * UTF-8 BOM prepended so Excel on Windows renders non-ASCII correctly.
 *
 * Hard cap: contact_ids capped at 1000 (vs the previous 5000) to stay well
 * under PostgREST's URL/header length limits when building the IN clause.
 * Caller-supplied lists exceeding 1000 are rejected with 400 rather than
 * silently truncated.
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAdmin } from "../_shared/auth.ts";

interface ExportRequest {
  format?: "csv";
  fields?: string[];
  contact_ids?: string[];
  limit?: number;
}

const ALLOWED_FIELDS = [
  // identity
  "email",
  "first_name",
  "last_name",
  "role",
  "department",
  "phone",
  "notes",
  // org
  "organization_name",
  "organization_industry",
  "parent_organization_name",
  // status
  "lead_classification",
  "engagement_level",
  "lead_score",
  // stats
  "thread_count",
  "total_emails",
  "emails_received",
  "emails_sent",
  "last_contact_at",
  "reply_rate",
  // AI
  "engagement_summary",
  "engagement_summary_at",
  // bookkeeping
  "contact_created_at",
  "contact_updated_at",
];

const DEFAULT_FIELDS = [
  "email",
  "first_name",
  "last_name",
  "role",
  "department",
  "phone",
  "organization_name",
  "lead_classification",
  "thread_count",
  "total_emails",
  "last_contact_at",
];

function escapeCsvCell(value: unknown): string {
  if (value === null || value === undefined) return "";
  let s: string;
  if (Array.isArray(value)) {
    s = value.map((v) => String(v)).join("; ");
  } else if (typeof value === "object") {
    s = JSON.stringify(value);
  } else {
    s = String(value);
  }
  // RFC 4180 escaping: wrap in quotes if contains comma, quote, or newline.
  // Quotes in the value are doubled.
  if (s.includes('"') || s.includes(",") || s.includes("\n") || s.includes("\r")) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}

function buildCsv(fields: string[], rows: Record<string, unknown>[]): string {
  const header = fields.join(",");
  const body = rows
    .map((row) => fields.map((f) => escapeCsvCell(row[f])).join(","))
    .join("\n");
  return `${header}\n${body}\n`;
}

function isoStamp(): string {
  // YYYY-MM-DD-HHMM, local-irrelevant (UTC)
  const d = new Date();
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}-${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const auth = await requireAdmin(req);
    if (auth instanceof Response) return auth;

    let body: ExportRequest;
    try {
      body = (await req.json()) as ExportRequest;
    } catch (_e) {
      return new Response(
        JSON.stringify({ success: false, error: "Invalid JSON body" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const format = body.format ?? "csv";
    if (format !== "csv") {
      return new Response(
        JSON.stringify({ success: false, error: `Unsupported format: ${format}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Validate field list against whitelist; fall back to defaults if empty.
    const requestedFields =
      Array.isArray(body.fields) && body.fields.length > 0 ? body.fields : DEFAULT_FIELDS;
    const fields = requestedFields.filter((f) => ALLOWED_FIELDS.includes(f));
    if (fields.length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `No valid fields. Allowed: ${ALLOWED_FIELDS.join(", ")}`,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const MAX_LIMIT = 5000;
    const MAX_CONTACT_IDS = 1000;
    const limit = Math.min(Math.max(1, body.limit ?? 2000), MAX_LIMIT);

    if (Array.isArray(body.contact_ids) && body.contact_ids.length > MAX_CONTACT_IDS) {
      return new Response(
        JSON.stringify({
          success: false,
          error: `contact_ids exceeds the per-request cap of ${MAX_CONTACT_IDS} (got ${body.contact_ids.length}). Either narrow your filter or omit contact_ids to export all.`,
          requested: body.contact_ids.length,
          max: MAX_CONTACT_IDS,
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Pull from v_contact_engagement_profile so org joins + per-contact stats
    // are pre-computed. Select the union of fields-being-exported AND
    // contact_id (always needed for stable row identity / future merges).
    const selectCols = ["contact_id", ...fields].join(",");
    let query = supabase.from("v_contact_engagement_profile").select(selectCols).limit(limit);

    if (Array.isArray(body.contact_ids) && body.contact_ids.length > 0) {
      query = query.in("contact_id", body.contact_ids);
    }

    // Stable order so re-exports are diffable.
    query = query.order("email", { ascending: true });

    const { data, error } = await query;
    if (error) {
      // Defensive: if the view doesn't exist (PR #74 hasn't shipped), surface
      // a helpful 503 rather than a generic 500 so operators understand the
      // dependency.
      const msg = (error as { message?: string }).message ?? String(error);
      if (msg.includes("v_contact_engagement_profile") || msg.includes("relation") && msg.includes("does not exist")) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "Contacts export view not yet deployed. Apply the v_contact_engagement_profile migration first.",
          }),
          { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
        );
      }
      throw error;
    }

    const rows = (data ?? []) as Record<string, unknown>[];
    // Prepend UTF-8 BOM so Excel on Windows renders non-ASCII characters
    // (accented names, AI-generated narrative summaries) correctly.
    const csv = "﻿" + buildCsv(fields, rows);

    const filename = `contacts-${isoStamp()}.csv`;

    return new Response(
      JSON.stringify({
        success: true,
        filename,
        mime: "text/csv",
        content: csv,
        rows: rows.length,
        fields,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("contacts-export failed:", err);
    return new Response(
      JSON.stringify({
        success: false,
        error: err instanceof Error ? err.message : String(err),
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
