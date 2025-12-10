// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "https://esm.sh/resend@latest";
import { encode as base64Encode } from "https://deno.land/std@0.168.0/encoding/base64.ts";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";

// Default fallback from email if mailbox not found
const DEFAULT_FROM_EMAIL = "noreply@pdmedical.com.au";

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

// Interface for signature images stored in mailboxes.signature_images
interface SignatureImage {
  cid: string;
  storage_path: string;
  filename: string;
  content_type: string;
}

// Helper to convert Blob to base64 string
async function blobToBase64(blob: Blob): Promise<string> {
  const arrayBuffer = await blob.arrayBuffer();
  const uint8Array = new Uint8Array(arrayBuffer);
  return base64Encode(uint8Array);
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1) Find drafts that are approved/auto_approved and not yet sent
    const { data: drafts, error: selectError } = await supabaseAdmin
      .from("email_drafts")
      .select(
        "id, subject, body_html, body_plain, to_emails, cc_emails, bcc_emails, thread_id, conversation_id, from_mailbox_id, sent_email_id, sent_at, contact_id, workflow_execution_id, campaign_enrollment_id, source_email_id"
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
        // 2) Fetch mailbox email, signature and signature_images
        let mailboxEmail = DEFAULT_FROM_EMAIL;
        let signatureHtml = "";
        let signatureImages: SignatureImage[] = [];

        if (draft.from_mailbox_id) {
          const { data: mailbox, error: mailboxError } = await supabaseAdmin
            .from("mailboxes")
            .select("email, signature_html, signature_images")
            .eq("id", draft.from_mailbox_id)
            .single();

          if (mailboxError) {
            console.warn("Failed to fetch mailbox:", mailboxError);
          } else if (mailbox) {
            mailboxEmail = mailbox.email || DEFAULT_FROM_EMAIL;
            signatureHtml = mailbox.signature_html || "";
            signatureImages = (mailbox.signature_images as SignatureImage[]) || [];
          }
        }

        // 3) Build threading headers if this is a reply
        let inReplyTo: string | null = null;
        let emailReferences: string | null = null;

        if (draft.source_email_id) {
          const { data: sourceEmail, error: sourceError } = await supabaseAdmin
            .from("emails")
            .select("message_id, email_references")
            .eq("id", draft.source_email_id)
            .single();

          if (sourceEmail && !sourceError) {
            inReplyTo = sourceEmail.message_id;
            // Build References: previous references + source message_id
            if (sourceEmail.email_references) {
              emailReferences = `${sourceEmail.email_references} ${sourceEmail.message_id}`;
            } else {
              emailReferences = sourceEmail.message_id;
            }
          }
        }

        // 4) Build attachments array for CID-embedded signature images
        const attachments: Array<{
          filename: string;
          content: string;
          content_id: string;
        }> = [];

        for (const img of signatureImages) {
          try {
            // Download image from Supabase Storage
            const { data: fileData, error: downloadError } = await supabaseAdmin.storage
              .from("internal")
              .download(img.storage_path);

            if (downloadError || !fileData) {
              console.warn(`Failed to download signature image ${img.cid}:`, downloadError);
              continue;
            }

            // Convert to base64
            const base64Content = await blobToBase64(fileData);

            attachments.push({
              filename: img.filename,
              content: base64Content,
              content_id: img.cid, // This enables cid: references in HTML
            });
          } catch (imgErr) {
            console.warn(`Error processing signature image ${img.cid}:`, imgErr);
          }
        }

        // 5) Combine body with signature
        const bodyHtml = draft.body_html ?? draft.body_plain ?? "";
        const fullHtml = signatureHtml ? `${bodyHtml}<br/><br/>${signatureHtml}` : bodyHtml;

        // 6) Build Resend tags for tracking (used by resend-webhook)
        const tags: Array<{ name: string; value: string }> = [
          { name: "draft_id", value: draft.id },
        ];
        if (draft.contact_id) {
          tags.push({ name: "contact_id", value: draft.contact_id });
        }
        if (draft.workflow_execution_id) {
          tags.push({ name: "workflow_execution_id", value: draft.workflow_execution_id });
        }
        if (draft.campaign_enrollment_id) {
          tags.push({ name: "campaign_enrollment_id", value: draft.campaign_enrollment_id });
        }

        // 7) Build email payload for Resend
        const emailPayload: {
          from: string;
          to: string[];
          cc?: string[];
          bcc?: string[];
          subject: string;
          html: string;
          attachments?: typeof attachments;
          tags?: typeof tags;
          headers?: Record<string, string>;
        } = {
          from: mailboxEmail,
          to: draft.to_emails,
          subject: draft.subject,
          html: fullHtml,
          tags,
        };

        // Include CC if specified
        if (draft.cc_emails && draft.cc_emails.length > 0) {
          emailPayload.cc = draft.cc_emails;
        }

        // Include BCC if specified
        if (draft.bcc_emails && draft.bcc_emails.length > 0) {
          emailPayload.bcc = draft.bcc_emails;
        }

        // Only include attachments if we have any
        if (attachments.length > 0) {
          emailPayload.attachments = attachments;
        }

        // Add threading headers for replies
        if (inReplyTo) {
          emailPayload.headers = {
            'In-Reply-To': `<${inReplyTo}>`,
          };
          if (emailReferences) {
            // Format each reference with angle brackets
            const formattedRefs = emailReferences
              .split(' ')
              .filter(id => id.trim())
              .map(id => id.startsWith('<') ? id : `<${id}>`)
              .join(' ');
            emailPayload.headers['References'] = formattedRefs;
          }
        }

        // 8) Send email via Resend
        const resendResponse = await resend.emails.send(emailPayload);
        const resendMessageId = resendResponse.data?.id || crypto.randomUUID();

        const nowIso = new Date().toISOString();

        // 9) Insert record into emails table
        const { data: emailRow, error: emailError } = await supabaseAdmin
          .from("emails")
          .insert({
            message_id: resendMessageId,
            thread_id: draft.thread_id || crypto.randomUUID(),
            conversation_id: draft.conversation_id,
            in_reply_to: inReplyTo,
            email_references: emailReferences,
            from_email: mailboxEmail,
            to_emails: draft.to_emails,
            cc_emails: draft.cc_emails || [],
            bcc_emails: draft.bcc_emails || [],
            subject: draft.subject,
            body_html: fullHtml,
            body_plain: draft.body_plain,
            mailbox_id: draft.from_mailbox_id,
            contact_id: draft.contact_id,
            direction: "outgoing",
            imap_folder: "Sent",
            sent_at: nowIso,
            received_at: nowIso,
          })
          .select("id")
          .single();

        if (emailError || !emailRow) {
          console.error("Failed to insert email record", emailError);
          continue;
        }

        // 10) Mark draft as sent and link to emails row
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

        console.log(`Sent email for draft ${draft.id} via ${mailboxEmail}, Resend ID: ${resendMessageId}`);
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
