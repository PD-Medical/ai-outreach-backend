// @ts-nocheck
// TEMPORARY VERSION FOR TESTING - SIGNATURE VERIFICATION DISABLED
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.3";
import { corsHeaders } from "../_shared/cors.ts";

type ResendTag = { name?: string; value?: string };

type ResendEvent = {
  type: string;
  data: {
    id?: string;
    email_id?: string;
    created_at?: string;
    to?: string[] | string;
    tags?: ResendTag[] | Record<string, string>;
    metadata?: Record<string, string>;
    subject?: string;
  };
};

type CampaignEventType =
  | "sent"
  | "delivered"
  | "opened"
  | "clicked"
  | "bounced"
  | "complained";

const SCORE_MAP: Record<CampaignEventType, number> = {
  sent: 1,
  delivered: 2,
  opened: 3,
  clicked: 4,
  bounced: -10,
  complained: -25,
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_WEBHOOK_SECRET = Deno.env.get("RESEND_WEBHOOK_SECRET") ?? "";

if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  throw new Error("Missing Supabase environment variables");
}

const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
  },
});

function normalizeEmail(value: string | string[] | undefined): string | null {
  if (!value) return null;
  if (Array.isArray(value) && value.length > 0) {
    return value[0]?.toLowerCase() ?? null;
  }
  if (typeof value === "string") {
    return value.toLowerCase();
  }
  return null;
}

function extractCampaignIdentifier(event: ResendEvent): { campaignId: string | null } {
  let campaignId: string | null = null;

  const tags = event.data.tags;
  if (Array.isArray(tags)) {
    for (const tag of tags) {
      if (!tag) continue;
      const key = tag.name?.toLowerCase();
      if (key === "campaign_id" || key === "campaign") {
        campaignId = tag.value ?? null;
      }
    }
  } else if (tags && typeof tags === "object") {
    for (const [key, value] of Object.entries(tags as Record<string, string>)) {
      if (!value) continue;
      if (key === "campaign_id" || key === "campaign") {
        campaignId = value;
      }
    }
  }

  if (!campaignId && event.data.metadata) {
    campaignId = event.data.metadata["campaign_id"] ?? campaignId;
  }

  return { campaignId };
}

function extractIdsFromTags(event: ResendEvent): {
  campaignEnrollmentId: string | null;
  workflowExecutionId: string | null;
  draftId: string | null;
  contactIdFromTag: string | null;
} {
  let campaignEnrollmentId: string | null = null;
  let workflowExecutionId: string | null = null;
  let draftId: string | null = null;
  let contactIdFromTag: string | null = null;

  const setFromKeyValue = (key: string, value: string) => {
    const lower = key.toLowerCase();
    switch (lower) {
      case "campaign_enrollment_id":
        campaignEnrollmentId = value;
        break;
      case "workflow_execution_id":
        workflowExecutionId = value;
        break;
      case "draft_id":
        draftId = value;
        break;
      case "contact_id":
        contactIdFromTag = value;
        break;
      default:
        break;
    }
  };

  const tags = event.data.tags;
  if (Array.isArray(tags)) {
    for (const tag of tags) {
      if (!tag?.name || !tag.value) continue;
      setFromKeyValue(tag.name, tag.value);
    }
  } else if (tags && typeof tags === "object") {
    for (const [key, value] of Object.entries(tags as Record<string, string>)) {
      if (!value) continue;
      setFromKeyValue(key, value);
    }
  }

  if (event.data.metadata) {
    for (const [key, value] of Object.entries(event.data.metadata)) {
      if (!value) continue;
      setFromKeyValue(key, value);
    }
  }

  return {
    campaignEnrollmentId,
    workflowExecutionId,
    draftId,
    contactIdFromTag,
  };
}

function mapResendTypeToCampaignEvent(type: string): CampaignEventType | null {
  switch (type) {
    case "email.sent":
      return "sent";
    case "email.delivered":
      return "delivered";
    case "email.opened":
      return "opened";
    case "email.clicked":
      return "clicked";
    case "email.bounced":
      return "bounced";
    case "email.complained":
      return "complained";
    default:
      return null;
  }
}

async function verifySignature(payload: string, signature: string | null): Promise<boolean> {
  // TEMPORARILY DISABLED FOR TESTING
  console.log("⚠️ SIGNATURE VERIFICATION DISABLED FOR TESTING");
  console.log("Secret configured:", !!RESEND_WEBHOOK_SECRET);
  console.log("Signature received:", !!signature);
  return true; // REMOVE THIS AFTER TESTING!
  
  /* ORIGINAL CODE - RE-ENABLE AFTER TESTING
  if (!RESEND_WEBHOOK_SECRET || !signature) {
    return false;
  }

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(RESEND_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const signatureBytes = Uint8Array.from(atob(signature), (c) => c.charCodeAt(0));
  const payloadBytes = encoder.encode(payload);

  const valid = await crypto.subtle.verify("HMAC", key, signatureBytes, payloadBytes);

  return valid;
  */
}

async function upsertCampaignSummary(args: {
  campaignId: string;
  contactId: string;
  eventType: CampaignEventType;
  scoreDelta: number;
  eventTimestamp: string;
  email: string;
  isWorkflow: boolean;
}) {
  const { campaignId, contactId, eventType, scoreDelta, eventTimestamp, email, isWorkflow } = args;

  const { data: existing, error: fetchError } = await supabaseAdmin
    .from("campaign_contact_summary")
    .select("*")
    .eq("campaign_id", campaignId)
    .eq("contact_id", contactId)
    .maybeSingle();

  if (fetchError) {
    console.error("Failed to load campaign_contact_summary", fetchError);
    throw fetchError;
  }

  const base: any = existing ?? {};

  const totalScore = (base.total_score ?? 0) + scoreDelta;
  const firstEventAt = base.first_event_at ?? eventTimestamp;
  const lastEventAt = eventTimestamp;

  // Counters
  let emailsSent = base.emails_sent ?? 0;
  let emailsDelivered = base.emails_delivered ?? 0;
  let emailsOpened = base.emails_opened ?? 0;
  let emailsClicked = base.emails_clicked ?? 0;
  let emailsBounced = base.emails_bounced ?? 0;
  let emailsReplied = base.emails_replied ?? 0;
  let uniqueClicks = base.unique_clicks ?? 0;

  let workflowEmailsSent = base.workflow_emails_sent ?? 0;
  let workflowEmailsOpened = base.workflow_emails_opened ?? 0;
  let workflowEmailsClicked = base.workflow_emails_clicked ?? 0;

  // Per-event updates
  if (eventType === "sent") {
    emailsSent += 1;
    if (isWorkflow) workflowEmailsSent += 1;
  } else if (eventType === "delivered") {
    emailsDelivered += 1;
  } else if (eventType === "opened") {
    emailsOpened += 1;
    if (isWorkflow) workflowEmailsOpened += 1;
  } else if (eventType === "clicked") {
    emailsClicked += 1;
    if (isWorkflow) workflowEmailsClicked += 1;
    uniqueClicks += 1;
  } else if (eventType === "bounced") {
    emailsBounced += 1;
  } else if (eventType === "complained") {
    emailsReplied += 1;
  }

  // Timestamps for open/click
  let firstOpenedAt = base.first_opened_at ?? null;
  let lastOpenedAt = base.last_opened_at ?? null;
  let firstClickedAt = base.first_clicked_at ?? null;
  let lastClickedAt = base.last_clicked_at ?? null;

  if (eventType === "opened") {
    if (!firstOpenedAt) firstOpenedAt = eventTimestamp;
    lastOpenedAt = eventTimestamp;
  }
  if (eventType === "clicked") {
    if (!firstClickedAt) firstClickedAt = eventTimestamp;
    lastClickedAt = eventTimestamp;
  }

  const opened = emailsOpened > 0;
  const clicked = emailsClicked > 0;
  const converted = base.converted ?? false;

  if (existing) {
    const { error: updateError } = await supabaseAdmin
      .from("campaign_contact_summary")
      .update({
        total_score: totalScore,
        opened,
        clicked,
        converted,
        first_event_at: firstEventAt,
        last_event_at: lastEventAt,
        email,
        emails_sent: emailsSent,
        emails_delivered: emailsDelivered,
        emails_opened: emailsOpened,
        emails_clicked: emailsClicked,
        emails_bounced: emailsBounced,
        emails_replied: emailsReplied,
        unique_clicks: uniqueClicks,
        first_opened_at: firstOpenedAt,
        last_opened_at: lastOpenedAt,
        first_clicked_at: firstClickedAt,
        last_clicked_at: lastClickedAt,
        workflow_emails_sent: workflowEmailsSent,
        workflow_emails_opened: workflowEmailsOpened,
        workflow_emails_clicked: workflowEmailsClicked,
      })
      .eq("campaign_id", campaignId)
      .eq("contact_id", contactId);

    if (updateError) {
      console.error("Failed to update campaign_contact_summary", updateError);
      throw updateError;
    }
  } else {
    const { error: insertError } = await supabaseAdmin.from("campaign_contact_summary").insert({
      campaign_id: campaignId,
      contact_id: contactId,
      email,
      total_score: totalScore,
      opened,
      clicked,
      converted,
      first_event_at: firstEventAt,
      last_event_at: lastEventAt,
      emails_sent: emailsSent,
      emails_delivered: emailsDelivered,
      emails_opened: emailsOpened,
      emails_clicked: emailsClicked,
      emails_bounced: emailsBounced,
      emails_replied: emailsReplied,
      unique_clicks: uniqueClicks,
      first_opened_at: firstOpenedAt,
      last_opened_at: lastOpenedAt,
      first_clicked_at: firstClickedAt,
      last_clicked_at: lastClickedAt,
      workflow_emails_sent: workflowEmailsSent,
      workflow_emails_opened: workflowEmailsOpened,
      workflow_emails_clicked: workflowEmailsClicked,
    });

    if (insertError) {
      console.error("Failed to insert campaign_contact_summary", insertError);
      throw insertError;
    }
  }
}

async function handleResendEvent(event: ResendEvent) {
  console.log("📥 Processing Resend event:", event.type);
  
  const campaignEventType = mapResendTypeToCampaignEvent(event.type);
  if (!campaignEventType) {
    console.log(`Ignoring unsupported Resend event type: ${event.type}`);
    return { status: 202, body: { success: true, message: "Event ignored" } };
  }

  const email = normalizeEmail(event.data.to);
  console.log("📧 Email:", email);
  
  if (!email) {
    return { status: 400, body: { success: false, message: "Missing recipient email" } };
  }

  const { data: contact, error: contactError } = await supabaseAdmin
    .from("contacts")
    .select("id")
    .eq("email", email)
    .maybeSingle();

  if (contactError) {
    console.error("Failed to fetch contact", contactError);
    return { status: 500, body: { success: false, message: "Failed to load contact" } };
  }

  if (!contact) {
    console.warn(`Contact not found for email ${email}. Skipping event.`);
    return {
      status: 202,
      body: { success: true, message: "Contact not found; event skipped" },
    };
  }

  console.log("✅ Contact found:", contact.id);

  const { campaignId } = extractCampaignIdentifier(event);
  console.log("🎯 Campaign ID:", campaignId);

  if (!campaignId) {
    console.warn(`No campaign_id tag for Resend event ${event.type}; skipping engagement record.`);
    return {
      status: 202,
      body: { success: true, message: "Campaign not matched; event skipped" },
    };
  }

  const { campaignEnrollmentId, workflowExecutionId, draftId } = extractIdsFromTags(event);
  const isWorkflow = !!workflowExecutionId;
  
  console.log("📊 Tags extracted:", {
    campaignEnrollmentId,
    workflowExecutionId,
    draftId,
    isWorkflow
  });

  const eventTimestamp = event.data.created_at ?? new Date().toISOString();
  const score = SCORE_MAP[campaignEventType];

  const { error: insertError } = await supabaseAdmin.from("campaign_events").insert({
    campaign_id: campaignId,
    campaign_enrollment_id: campaignEnrollmentId,
    workflow_execution_id: workflowExecutionId,
    draft_id: draftId,
    contact_id: contact.id,
    email,
    event_type: campaignEventType,
    event_timestamp: eventTimestamp,
    score,
    source: {
      provider: "resend",
      resend_event_id: event.data.id,
      resend_email_id: event.data.email_id,
      subject: event.data.subject,
      type: event.type,
      tags: event.data.tags ?? null,
      metadata: event.data.metadata ?? null,
      is_workflow: isWorkflow,
    },
  });

  if (insertError) {
    console.error("❌ Failed to insert campaign event", insertError);
    throw insertError;
  }

  console.log("✅ Campaign event inserted");

  await upsertCampaignSummary({
    campaignId,
    contactId: contact.id,
    eventType: campaignEventType,
    scoreDelta: score,
    eventTimestamp,
    email,
    isWorkflow,
  });

  console.log("✅ Campaign summary updated");

  return {
    status: 200,
    body: { success: true, message: "Resend event processed" },
  };
}

serve(async (request) => {
  console.log("🔔 Webhook called:", request.method);
  
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return new Response(JSON.stringify({ success: false, message: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  const rawBody = await request.text();
  const signature = request.headers.get("resend-signature");

  if (!(await verifySignature(rawBody, signature))) {
    return new Response(JSON.stringify({ success: false, message: "Invalid signature" }), {
      status: 401,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  let event: ResendEvent;

  try {
    event = JSON.parse(rawBody) as ResendEvent;
  } catch (error) {
    console.error("Failed to parse Resend event body", error);
    return new Response(JSON.stringify({ success: false, message: "Invalid JSON payload" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  try {
    const result = await handleResendEvent(event);
    return new Response(JSON.stringify(result.body), {
      status: result.status,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  } catch (error) {
    console.error("Unhandled error processing Resend event", error);
    return new Response(JSON.stringify({ success: false, message: "Internal error" }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});