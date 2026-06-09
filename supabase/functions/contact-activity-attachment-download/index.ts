/**
 * Contact Activity Attachment Download
 *
 * Authenticated proxy that returns a short-lived signed URL for a timeline
 * attachment. Files are stored in the private `crm-activity-attachments` bucket;
 * callers never sign arbitrary storage paths directly from the browser.
 *
 * Request body: { attachment_id: string }
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const SIGNED_URL_TTL_SECONDS = 60;

function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Method not allowed" }, 405);
  }

  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;

  let body: { attachment_id?: string };
  try {
    body = await req.json();
  } catch (_e) {
    return jsonResponse({ success: false, error: "Invalid JSON body" }, 400);
  }

  if (!body.attachment_id || !UUID_RE.test(body.attachment_id)) {
    return jsonResponse({ success: false, error: "attachment_id must be a UUID" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: attachment, error: attachmentError } = await supabase
    .from("contact_activity_attachments")
    .select(`
      id,
      storage_bucket,
      storage_path,
      file_name,
      contact_activities!inner (
        id,
        deleted_at
      )
    `)
    .eq("id", body.attachment_id)
    .is("contact_activities.deleted_at", null)
    .maybeSingle();

  if (attachmentError) {
    console.error("attachment lookup failed", attachmentError);
    return jsonResponse({ success: false, error: "Attachment lookup failed" }, 500);
  }
  if (!attachment) {
    return jsonResponse({ success: false, error: "Attachment not found" }, 404);
  }

  const bucket = attachment.storage_bucket || "crm-activity-attachments";
  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(attachment.storage_path, SIGNED_URL_TTL_SECONDS, {
      download: attachment.file_name,
    });

  if (error || !data?.signedUrl) {
    console.error("signed url creation failed", error);
    return jsonResponse({ success: false, error: "Unable to create download link" }, 500);
  }

  return jsonResponse({
    success: true,
    signed_url: data.signedUrl,
    file_name: attachment.file_name,
    expires_in: SIGNED_URL_TTL_SECONDS,
  });
});
