// @ts-nocheck
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

if (!RESEND_WEBHOOK_SECRET) {
  console.warn("RESEND_WEBHOOK_SECRET is not set. Webhook verification will fail.");
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

function extractCampaignIdentifier(event: ResendEvent): {
  campaignId: string | null;
  campaignExternalId: string | null;
} {
  let campaignId: string | null = null;
  let externalId: string | null = event.data.email_id ?? event.data.id ?? null;

  const tags = event.data.tags;
  if (Array.isArray(tags)) {
    for (const tag of tags) {
      if (!tag) continue;
      const key = tag.name?.toLowerCase();
      if (key === "campaign_id" || key === "campaign") {
        campaignId = tag.value ?? null;
      }
      if (key === "campaign_external_id" && tag.value) {
        externalId = tag.value;
      }
    }
  } else if (tags && typeof tags === "object") {
    const keys = Object.keys(tags);
    for (const key of keys) {
      const value = (tags as Record<string, string>)[key];
      if (key === "campaign_id" || key === "campaign") {
        campaignId = value;
      }
      if (key === "campaign_external_id") {
        externalId = value;
      }
    }
  }

  if (!campaignId && event.data.metadata) {
    campaignId = event.data.metadata["campaign_id"] ?? campaignId;
    externalId = event.data.metadata["campaign_external_id"] ?? externalId;
  }

  return {
    campaignId,
    campaignExternalId: externalId,
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
}

async function upsertCampaignSummary(args: {
  campaignId: string;
  contactId: string;
  eventType: CampaignEventType;
  scoreDelta: number;
  eventTimestamp: string;
  email: string;
}) {
  const { campaignId, contactId, eventType, scoreDelta, eventTimestamp, email } = args;

  const { data: existing, error: fetchError } = await supabaseAdmin
    .from("campaign_contact_summary")
    .select("campaign_id, contact_id, total_score, opened, clicked, converted, first_event_at, last_event_at")
    .eq("campaign_id", campaignId)
    .eq("contact_id", contactId)
    .maybeSingle();

  if (fetchError) {
    console.error("Failed to load campaign_contact_summary", fetchError);
    throw fetchError;
  }

  const opened = eventType === "opened" ? true : existing?.opened ?? false;
  const clicked = eventType === "clicked" ? true : existing?.clicked ?? false;
  const converted = existing?.converted ?? false;
  const firstEventAt = existing?.first_event_at ?? eventTimestamp;
  const lastEventAt = eventTimestamp;
  const totalScore = (existing?.total_score ?? 0) + scoreDelta;

  if (existing) {
    const { error: updateError } = await supabaseAdmin
      .from("campaign_contact_summary")
      .update({
        total_score: totalScore,
        opened,
        clicked,
        converted,
        last_event_at: lastEventAt,
        email,
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
    });

    if (insertError) {
      console.error("Failed to insert campaign_contact_summary", insertError);
      throw insertError;
    }
  }
}

async function handleResendEvent(event: ResendEvent) {
  const campaignEventType = mapResendTypeToCampaignEvent(event.type);
  if (!campaignEventType) {
    console.log(`Ignoring unsupported Resend event type: ${event.type}`);
    return { status: 202, body: { success: true, message: "Event ignored" } };
  }

  const email = normalizeEmail(event.data.to);
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

  const { campaignId, campaignExternalId } = extractCampaignIdentifier(event);
  let resolvedCampaignId: string | null = campaignId;

  if (!resolvedCampaignId && campaignExternalId) {
    const { data: campaign, error: campaignError } = await supabaseAdmin
      .from("campaigns")
      .select("id")
      .eq("external_id", campaignExternalId)
      .maybeSingle();

    if (campaignError) {
      console.error("Failed to fetch campaign by external_id", campaignError);
      return { status: 500, body: { success: false, message: "Failed to load campaign" } };
    }

    resolvedCampaignId = campaign?.id ?? null;
  }

  if (!resolvedCampaignId) {
    console.warn(`No campaign match for Resend event ${event.type} (email_id=${campaignExternalId})`);
    return {
      status: 202,
      body: { success: true, message: "Campaign not matched; event recorded without campaign" },
    };
  }

  const eventTimestamp =
    event.data.created_at ?? new Date().toISOString();

  const score = SCORE_MAP[campaignEventType];

  const { error: insertError } = await supabaseAdmin.from("campaign_events").insert({
    campaign_id: resolvedCampaignId,
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
    },
    external_id: event.data.email_id ?? event.data.id ?? null,
  });

  if (insertError) {
    console.error("Failed to insert campaign event", insertError);
    throw insertError;
  }

  await upsertCampaignSummary({
    campaignId: resolvedCampaignId,
    contactId: contact.id,
    eventType: campaignEventType,
    scoreDelta: score,
    eventTimestamp,
    email,
  });

  return {
    status: 200,
    body: { success: true, message: "Resend event processed" },
  };
}

serve(async (request) => {
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


