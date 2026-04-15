/**
 * Learn Persona Edge Function
 *
 * Invokes the learn-persona Lambda to build (or refresh) a mailbox's
 * structured writing-voice profile from its own past sent emails.
 *
 * Request body:
 *   {
 *     mailbox_id: string,
 *     max_emails?: number   // optional, defaults to 60
 *   }
 *
 * The Lambda reads the mailbox's human-written outgoing emails (those with
 * no linked email_drafts row, i.e. sent directly via IMAP rather than
 * composed in the AI system), passes ~60 of them to an LLM with a Pydantic
 * schema, and writes the resulting profile into mailboxes.persona_profile.
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

interface LearnPersonaRequest {
  mailbox_id: string;
  max_emails?: number;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const auth = await requireAuth(req);
    if (auth instanceof Response) return auth;
    const { user } = auth;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    const body: LearnPersonaRequest = await req.json();
    const { mailbox_id, max_emails } = body;

    if (!mailbox_id) {
      return new Response(
        JSON.stringify({ error: "Missing required field: mailbox_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Verify mailbox exists
    const { data: mailbox, error: mailboxError } = await supabase
      .from("mailboxes")
      .select("id, email, name, is_active")
      .eq("id", mailbox_id)
      .single();

    if (mailboxError || !mailbox) {
      return new Response(
        JSON.stringify({ error: "Mailbox not found", details: mailboxError }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // User is already authenticated via requireAuth above.
    // Mailbox existence was verified. Permission is implicit — all authenticated
    // users with access to the app can trigger persona learning for any mailbox.

    // Resolve Lambda URL from system_config
    const { data: configData, error: configError } = await supabase
      .from("system_config")
      .select("value")
      .eq("key", "learn_persona_url")
      .single();

    const lambdaUrl = configData?.value;
    if (configError || !lambdaUrl) {
      console.error("learn_persona_url not found in system_config:", configError);
      return new Response(
        JSON.stringify({ error: "Persona learning service not configured" }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    console.log(`User ${user.id} learning persona for mailbox ${mailbox.email}`);

    const lambdaResponse = await fetch(lambdaUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        mailbox_id,
        max_emails: max_emails ?? 60,
      }),
    });

    const lambdaResult = await lambdaResponse.json();

    if (!lambdaResponse.ok) {
      return new Response(
        JSON.stringify({
          error: "Persona learning failed",
          details: lambdaResult,
        }),
        { status: lambdaResponse.status, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    return new Response(
      JSON.stringify(lambdaResult),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (error) {
    console.error("Error in learn-persona edge function:", error);
    return new Response(
      JSON.stringify({ error: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
