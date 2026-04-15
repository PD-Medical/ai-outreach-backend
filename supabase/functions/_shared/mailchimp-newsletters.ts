import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

const MAILCHIMP_REPLY_HOST_MARKERS = ['rsgsv.net', 'mcsv.net', 'mailchimpapp.net'];

// Matches Mailchimp's in_reply_to / references format. Example:
//   dbf3676ae72647d2716973162.ad0a015381.20260325222934.fa6288cf73.660aebd8@mail75.atl51.rsgsv.net
// The 4th dot-segment is the 10-char hex campaign ID.
const MAILCHIMP_CAMPAIGN_ID_PATTERN =
  /\.([a-f0-9]{10})\.[a-f0-9]+@mail[^.]+\.[^.]+\.(?:rsgsv|mcsv|mailchimpapp)\.net/i;

export interface MailchimpNewsletter {
  id: string;
  mailchimp_campaign_id: string;
  title?: string | null;
  subject: string;
  normalized_subject: string;
  from_name?: string | null;
  reply_to_email?: string | null;
  mailbox_id?: string | null;
  audience_id?: string | null;
  archive_url?: string | null;
  status?: string | null;
  sent_at?: string | null;
  html_content?: string | null;
  plain_content?: string | null;
  raw_payload?: Record<string, unknown>;
}

interface MailchimpCampaign {
  id: string;
  settings?: {
    title?: string;
    subject_line?: string;
    reply_to?: string;
    from_name?: string;
  };
  recipients?: {
    list_id?: string;
  };
  archive_url?: string;
  status?: string;
  send_time?: string;
}

interface MailchimpCampaignContent {
  html?: string;
  plain_text?: string;
}

interface MailchimpCampaignListResponse {
  campaigns?: MailchimpCampaign[];
}

export function normalizeMailchimpNewsletterSubject(subject?: string | null): string {
  if (!subject) return '';

  return subject
    .replace(/^(automatic reply|auto reply|autoreply|automatic response|out of office|ooo|re|fw|fwd):\s*/gi, '')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

export function isLikelyMailchimpReply(input: {
  subject?: string | null;
  in_reply_to?: string | null;
  email_references?: string | null;
}): boolean {
  const subject = input.subject ?? '';
  const subjectSignal = /^(automatic reply|auto reply|autoreply|automatic response|out of office|ooo):/i.test(subject);
  const replyHeaders = `${input.in_reply_to ?? ''} ${input.email_references ?? ''}`.toLowerCase();
  const headerSignal = MAILCHIMP_REPLY_HOST_MARKERS.some(marker => replyHeaders.includes(marker));
  return subjectSignal || headerSignal;
}

export function extractMailchimpCampaignId(
  inReplyTo?: string | null,
  references?: string | null,
): string | null {
  const sources = [inReplyTo, references].filter((s): s is string => !!s);
  for (const source of sources) {
    const match = source.match(MAILCHIMP_CAMPAIGN_ID_PATTERN);
    if (match?.[1]) return match[1];
  }
  return null;
}

export interface MailchimpLinkResult {
  newsletterId: string;
  method: 'header_campaign_id' | 'normalized_subject';
  confidence: number;
  reason: string;
}

/**
 * Try to link an inbound email to a Mailchimp newsletter.
 * Tier 1 (confidence 1.0): extract campaign ID from in_reply_to/references headers.
 * Tier 2 (confidence 0.85): match normalized subject within 60d of newsletter send.
 * Updates the emails row on match. Returns match info or null. Never throws.
 */
export async function linkEmailToMailchimpNewsletter(
  supabase: SupabaseClient,
  emailId: string,
  input: {
    subject?: string | null;
    in_reply_to?: string | null;
    email_references?: string | null;
    received_at?: string | null;
    mailbox_id?: string | null;
  },
): Promise<MailchimpLinkResult | null> {
  try {
    // Tier 1: campaign ID from headers
    const campaignId = extractMailchimpCampaignId(input.in_reply_to, input.email_references);
    if (campaignId) {
      const { data: newsletter } = await supabase
        .from('mailchimp_newsletters')
        .select('id')
        .eq('mailchimp_campaign_id', campaignId)
        .maybeSingle();

      if (newsletter?.id) {
        const result: MailchimpLinkResult = {
          newsletterId: newsletter.id,
          method: 'header_campaign_id',
          confidence: 1.0,
          reason: `Extracted campaign ID ${campaignId} from in_reply_to/references (Mailchimp relay)`,
        };
        await applyLink(supabase, emailId, result);
        return result;
      }
    }

    // Tier 2: normalized subject within 60 days of send
    const normalized = normalizeMailchimpNewsletterSubject(input.subject);
    if (!normalized) return null;

    const receivedAt = input.received_at ? new Date(input.received_at) : new Date();
    const windowStart = new Date(receivedAt.getTime() - 60 * 24 * 60 * 60 * 1000).toISOString();
    const windowEnd = new Date(receivedAt.getTime() + 24 * 60 * 60 * 1000).toISOString();

    let query = supabase
      .from('mailchimp_newsletters')
      .select('id, subject, mailbox_id, sent_at')
      .eq('normalized_subject', normalized)
      .gte('sent_at', windowStart)
      .lte('sent_at', windowEnd)
      .order('sent_at', { ascending: false })
      .limit(1);

    if (input.mailbox_id) {
      query = query.or(`mailbox_id.eq.${input.mailbox_id},mailbox_id.is.null`);
    }

    const { data: newsletter } = await query.maybeSingle();
    if (newsletter?.id) {
      const result: MailchimpLinkResult = {
        newsletterId: newsletter.id,
        method: 'normalized_subject',
        confidence: 0.85,
        reason: `Matched normalized subject to newsletter: ${newsletter.subject}`,
      };
      await applyLink(supabase, emailId, result);
      return result;
    }

    return null;
  } catch (err) {
    console.error('[mailchimp-link] Failed to link email to newsletter:', err);
    return null;
  }
}

async function applyLink(
  supabase: SupabaseClient,
  emailId: string,
  result: MailchimpLinkResult,
): Promise<void> {
  await supabase
    .from('emails')
    .update({
      mailchimp_newsletter_id: result.newsletterId,
      mailchimp_match_method: result.method,
      mailchimp_match_confidence: result.confidence,
      mailchimp_match_reason: result.reason,
    })
    .eq('id', emailId);
}

function getMailchimpApiKey(): string {
  const apiKey = Deno.env.get('MAILCHIMP_API_KEY');
  if (!apiKey) {
    throw new Error('MAILCHIMP_API_KEY environment variable is required');
  }
  return apiKey;
}

function getMailchimpBaseUrl(): string {
  const apiKey = getMailchimpApiKey();
  const serverPrefix = apiKey.split('-').pop();
  if (!serverPrefix) {
    throw new Error('Invalid MAILCHIMP_API_KEY format');
  }
  return `https://${serverPrefix}.api.mailchimp.com/3.0`;
}

async function mailchimpFetch<T>(path: string): Promise<T> {
  const apiKey = getMailchimpApiKey();
  const response = await fetch(`${getMailchimpBaseUrl()}${path}`, {
    headers: {
      Authorization: `Basic ${btoa(`anystring:${apiKey}`)}`,
      'Content-Type': 'application/json',
    },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Mailchimp API error ${response.status}: ${errorText}`);
  }

  return await response.json() as T;
}

function htmlToPlainText(html?: string | null): string | null {
  if (!html) return null;

  return html
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&#39;/gi, "'")
    .replace(/&quot;/gi, '"')
    .replace(/\n{3,}/g, '\n\n')
    .replace(/[ \t]{2,}/g, ' ')
    .trim();
}

async function resolveMailboxIdForReplyTo(
  supabase: SupabaseClient,
  replyToEmail?: string | null,
): Promise<string | null> {
  if (!replyToEmail) return null;

  const { data } = await supabase
    .from('mailboxes')
    .select('id')
    .eq('email', replyToEmail.toLowerCase())
    .maybeSingle();

  return data?.id ?? null;
}

export async function fetchMailchimpCampaign(campaignId: string): Promise<MailchimpCampaign> {
  return await mailchimpFetch<MailchimpCampaign>(`/campaigns/${campaignId}`);
}

export async function fetchMailchimpCampaignContent(campaignId: string): Promise<MailchimpCampaignContent> {
  return await mailchimpFetch<MailchimpCampaignContent>(`/campaigns/${campaignId}/content`);
}

export async function syncMailchimpCampaignToDb(
  supabase: SupabaseClient,
  campaignId: string,
): Promise<MailchimpNewsletter> {
  const [campaign, content] = await Promise.all([
    fetchMailchimpCampaign(campaignId),
    fetchMailchimpCampaignContent(campaignId),
  ]);

  const subject = campaign.settings?.subject_line?.trim();
  if (!subject) {
    throw new Error(`Mailchimp campaign ${campaignId} has no subject_line`);
  }

  const replyToEmail = campaign.settings?.reply_to?.toLowerCase() ?? null;
  const mailboxId = await resolveMailboxIdForReplyTo(supabase, replyToEmail);
  const plainContent = content.plain_text?.trim() || htmlToPlainText(content.html);

  const { data, error } = await supabase
    .from('mailchimp_newsletters')
    .upsert({
      mailchimp_campaign_id: campaign.id,
      title: campaign.settings?.title ?? subject,
      subject,
      normalized_subject: normalizeMailchimpNewsletterSubject(subject),
      from_name: campaign.settings?.from_name ?? null,
      reply_to_email: replyToEmail,
      mailbox_id: mailboxId,
      audience_id: campaign.recipients?.list_id ?? null,
      archive_url: campaign.archive_url ?? null,
      status: campaign.status ?? 'sent',
      sent_at: campaign.send_time ?? null,
      html_content: content.html ?? null,
      plain_content: plainContent,
      raw_payload: {
        campaign,
        content,
      },
      updated_at: new Date().toISOString(),
    }, { onConflict: 'mailchimp_campaign_id' })
    .select('*')
    .single();

  if (error || !data) {
    throw new Error(`Failed to upsert Mailchimp newsletter ${campaignId}: ${error?.message}`);
  }

  return data as MailchimpNewsletter;
}

export async function syncRecentMailchimpCampaignsToDb(
  supabase: SupabaseClient,
  options: {
    sentSince?: string;
    limit?: number;
  } = {},
): Promise<MailchimpNewsletter[]> {
  const limit = Math.min(Math.max(options.limit ?? 25, 1), 100);
  const sentSince = options.sentSince ? new Date(options.sentSince) : null;
  const results: MailchimpNewsletter[] = [];
  const pageSize = 100;
  let offset = 0;
  let reachedWindowBoundary = false;

  while (results.length < limit && !reachedWindowBoundary) {
    const campaignsPage = await mailchimpFetch<MailchimpCampaignListResponse>(
      `/campaigns?status=sent&count=${pageSize}&offset=${offset}&sort_field=send_time&sort_dir=DESC`,
    );

    const campaigns = campaignsPage.campaigns ?? [];
    if (campaigns.length === 0) {
      break;
    }

    for (const campaign of campaigns) {
      if (sentSince && campaign.send_time && new Date(campaign.send_time) < sentSince) {
        reachedWindowBoundary = true;
        break;
      }

      results.push(await syncMailchimpCampaignToDb(supabase, campaign.id));
      if (results.length >= limit) {
        break;
      }
    }

    if (campaigns.length < pageSize) {
      break;
    }

    offset += campaigns.length;
  }

  return results;
}

export function extractCampaignIdFromWebhookPayload(payload: Record<string, unknown>): string | null {
  const candidates = [
    payload.campaign_id,
    payload.id,
    (payload.data as Record<string, unknown> | undefined)?.campaign_id,
    (payload.data as Record<string, unknown> | undefined)?.id,
    (payload.campaign as Record<string, unknown> | undefined)?.id,
  ];

  for (const candidate of candidates) {
    if (typeof candidate === 'string' && candidate.trim()) {
      return candidate.trim();
    }
  }

  return null;
}

export async function logMailchimpNewsletterEvent(
  supabase: SupabaseClient,
  payload: Record<string, unknown>,
  options: {
    eventType?: string | null;
    campaignId?: string | null;
    processingStatus?: string;
    processingError?: string | null;
    processedAt?: string | null;
  } = {},
): Promise<void> {
  const { error } = await supabase
    .from('mailchimp_newsletter_events')
    .insert({
      event_type: options.eventType ?? null,
      mailchimp_campaign_id: options.campaignId ?? null,
      payload,
      processing_status: options.processingStatus ?? 'pending',
      processing_error: options.processingError ?? null,
      processed_at: options.processedAt ?? null,
    });

  if (error) {
    throw new Error(`Failed to log Mailchimp newsletter event: ${error.message}`);
  }
}
