// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "https://esm.sh/resend@latest";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";

// Fixed from-email as requested
const FROM_EMAIL = "peter@pdmedical.com.au";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  throw new Error("Missing Supabase environment variables");
}
if (!RESEND_API_KEY) {
  throw new Error("Missing RESEND_API_KEY");
}

const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

const resend = new Resend(RESEND_API_KEY);

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1) Find drafts that are approved/auto_approved and not yet sent
    const { data: drafts, error: selectError } = await supabaseAdmin
      .from("email_drafts")
      .select(
        "id, subject, body_html, body_plain, to_emails, thread_id, conversation_id, from_mailbox_id, sent_email_id, sent_at"
      )
      .in("approval_status", ["approved", "auto_approved"])
      .is("sent_email_id", null)
      .limit(20);

    if (selectError) {
      console.error("Failed to load drafts", selectError);
      return new Response("Error loading drafts", {
        status: 500,
        headers: corsHeaders,
      });
    }

    if (!drafts || drafts.length === 0) {
      return new Response(
        JSON.stringify({ success: true, processed: 0 }),
        { headers: { "Content-Type": "application/json", ...corsHeaders } },
      );
    }

    let processed = 0;

    for (const draft of drafts) {
      try {
        // 2) Send email via Resend using data from email_drafts
        await resend.emails.send({
          from: FROM_EMAIL,
          to: draft.to_emails,
          subject: draft.subject,
          html: draft.body_html ?? draft.body_plain,
        });

        const nowIso = new Date().toISOString();

        // 3) Insert record into emails table
        const { data: emailRow, error: emailError } = await supabaseAdmin
          .from("emails")
          .insert({
            message_id: crypto.randomUUID(),
            thread_id: draft.thread_id,
            conversation_id: draft.conversation_id,
            from_email: FROM_EMAIL,
            to_emails: draft.to_emails,
            subject: draft.subject,
            body_html: draft.body_html,
            body_plain: draft.body_plain,
            mailbox_id: draft.from_mailbox_id,
            direction: "outgoing",
            sent_at: nowIso,
            received_at: nowIso,
          })
          .select("id")
          .single();

        if (emailError || !emailRow) {
          console.error("Failed to insert email record", emailError);
          continue;
        }

        // 4) Mark draft as sent and link to emails row
        const { error: updateError } = await supabaseAdmin
          .from("email_drafts")
          .update({
            sent_email_id: emailRow.id,
            sent_at: nowIso,
            approval_status: "sent",
          })
          .eq("id", draft.id);

        if (updateError) {
          console.error("Failed to update draft as sent", updateError);
          continue;
        }

        processed += 1;
      } catch (err) {
        console.error("Error sending draft", draft.id, err);
      }
    }

    return new Response(
      JSON.stringify({ success: true, processed }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } },
    );
  } catch (err) {
    console.error("send-approved-drafts error", err);
    return new Response("Internal error", {
      status: 500,
      headers: corsHeaders,
    });
  }
});

