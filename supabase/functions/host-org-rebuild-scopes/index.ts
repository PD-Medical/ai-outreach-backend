// host-org-rebuild-scopes
// Recomputes emails.is_internal for rows that touch a specified host domain.
// Invoked from the Settings → Host Organizations UI after adding or removing
// a host org. Idempotent.
//
// Request body: { domain: "pdmedical.com.au" }
// Response: { reclassified: true, internal_now: <count> }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { domain } = (await req.json()) as { domain?: string };
    if (!domain || typeof domain !== "string") {
      return json({ error: "domain is required" }, 400);
    }
    const normalized = domain.trim().toLowerCase();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const { error } = await supabase.rpc("rebuild_email_scopes_for_domain", {
      p_domain: normalized,
    });

    if (error) {
      console.error("rebuild_email_scopes_for_domain failed", error);
      return json({ error: error.message }, 500);
    }

    const { count: internalNow } = await supabase
      .from("emails")
      .select("id", { count: "exact", head: true })
      .eq("is_internal", true);

    return json({ reclassified: true, internal_now: internalNow ?? 0 });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
