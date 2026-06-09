import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { mailchimpFetch } from './mailchimp-contacts.ts';

export type CampaignEventType = 'sent' | 'opened' | 'clicked' | 'bounced' | 'complained';

export interface MailchimpActivityItem {
  action?: string;
  timestamp?: string;
  created_at?: string;
  url?: string;
  type?: string;
  [key: string]: unknown;
}

export interface MailchimpEmailActivity {
  email_id?: string;
  email_address?: string;
  list_id?: string;
  campaign_id?: string;
  activity?: MailchimpActivityItem[];
  [key: string]: unknown;
}

interface MailchimpEmailActivityResponse {
  emails?: MailchimpEmailActivity[];
  total_items?: number;
}

export interface MailchimpNewsletterForEngagement {
  id: string;
  mailchimp_campaign_id: string;
  campaign_id?: string | null;
  title?: string | null;
  subject: string;
  audience_id?: string | null;
  sent_at?: string | null;
}

export interface MailchimpEngagementError {
  campaign_id?: string;
  email?: string;
  message: string;
}

export interface MailchimpEngagementStats {
  campaigns_scanned: number;
  activities_scanned: number;
  events_inserted: number;
  events_skipped_existing: number;
  contacts_matched: number;
  contacts_missing: number;
  summaries_updated: number;
  errors: MailchimpEngagementError[];
}

export interface MailchimpScoringState {
  openScored: boolean;
  scoredClickUrls: Set<string>;
  clickScoreTotal: number;
  bounceScored: boolean;
  unsubScored: boolean;
  abuseScored: boolean;
}

export interface MappedMailchimpActivity {
  action: string;
  eventType: CampaignEventType;
  timestamp: string;
  url: string | null;
}

export interface MailchimpActivityScore {
  score: number;
  scoringRule: string;
}

interface MailchimpActivityWithMapping {
  activity: MailchimpActivityItem;
  mapped: MappedMailchimpActivity;
}

interface PreparedMailchimpActivityRow {
  email: string;
  emailId: string | null;
  listId: string | null;
  mappedActivities: MailchimpActivityWithMapping[];
}

interface MailchimpCampaignBridge {
  campaignId: string | null;
  scoringKey: string;
}

interface MailchimpEngagementSyncOptions {
  dryRun?: boolean;
  maxEmailsPerCampaign?: number;
  fetchEmailActivityPage?: (
    campaignId: string,
    count: number,
    offset: number,
  ) => Promise<MailchimpEmailActivityResponse>;
}

export function mailchimpEngagementScheduleRateToCron(scheduleRate: string): string {
  switch (scheduleRate) {
    case '15 minutes':
      return '*/15 * * * *';
    case '30 minutes':
      return '*/30 * * * *';
    case '1 hour':
      return '0 * * * *';
    case '2 hours':
      return '0 */2 * * *';
    case '6 hours':
      return '0 */6 * * *';
    default:
      return '0 * * * *';
  }
}

export function normalizeMailchimpEmail(email: string | null | undefined): string {
  return (email ?? '').trim().toLowerCase();
}

function normalizeAction(action: string | null | undefined): string {
  return (action ?? '').trim().toLowerCase().replace(/[\s-]+/g, '_');
}

function normalizeUrl(url: string | null | undefined): string | null {
  const trimmed = (url ?? '').trim();
  return trimmed || null;
}

function activityTimestamp(activity: MailchimpActivityItem): string {
  const candidate = activity.timestamp ?? activity.created_at;
  if (candidate && !Number.isNaN(new Date(candidate).getTime())) {
    return new Date(candidate).toISOString();
  }
  return new Date().toISOString();
}

export function mapMailchimpActivity(activity: MailchimpActivityItem): MappedMailchimpActivity | null {
  const action = normalizeAction(activity.action ?? activity.type);
  if (!action) return null;

  if (action === 'sent' || action === 'send') {
    return { action: 'sent', eventType: 'sent', timestamp: activityTimestamp(activity), url: null };
  }

  if (action === 'open' || action === 'opened') {
    return { action: 'open', eventType: 'opened', timestamp: activityTimestamp(activity), url: null };
  }

  if (action === 'click' || action === 'clicked') {
    return { action: 'click', eventType: 'clicked', timestamp: activityTimestamp(activity), url: normalizeUrl(activity.url) };
  }

  if (action === 'bounce' || action === 'bounced' || action === 'hard_bounce' || action === 'soft_bounce') {
    return { action: 'bounce', eventType: 'bounced', timestamp: activityTimestamp(activity), url: null };
  }

  if (action === 'unsub' || action === 'unsubscribe' || action === 'unsubscribed') {
    return { action: 'unsub', eventType: 'complained', timestamp: activityTimestamp(activity), url: null };
  }

  if (action === 'abuse' || action === 'complaint' || action === 'complained' || action === 'spam') {
    return { action: 'abuse', eventType: 'complained', timestamp: activityTimestamp(activity), url: null };
  }

  return null;
}

export function createEmptyMailchimpScoringState(): MailchimpScoringState {
  return {
    openScored: false,
    scoredClickUrls: new Set<string>(),
    clickScoreTotal: 0,
    bounceScored: false,
    unsubScored: false,
    abuseScored: false,
  };
}

export function scoreMailchimpActivity(
  mapped: MappedMailchimpActivity,
  state: MailchimpScoringState,
): MailchimpActivityScore {
  if (mapped.action === 'sent') {
    return { score: 0, scoringRule: 'sent_zero_score' };
  }

  if (mapped.action === 'open') {
    if (state.openScored) return { score: 0, scoringRule: 'additional_open_zero_score' };
    return { score: 2, scoringRule: 'first_open_plus_2' };
  }

  if (mapped.action === 'click') {
    const urlKey = mapped.url ?? '__unknown_url__';
    if (state.scoredClickUrls.has(urlKey)) {
      return { score: 0, scoringRule: 'repeat_click_url_zero_score' };
    }

    if (state.clickScoreTotal >= 12) {
      return { score: 0, scoringRule: 'click_score_cap_reached' };
    }

    const baseScore = state.scoredClickUrls.size === 0 ? 8 : 2;
    const score = Math.min(baseScore, 12 - state.clickScoreTotal);
    return { score, scoringRule: state.scoredClickUrls.size === 0 ? 'first_unique_click_plus_8' : 'additional_unique_click_plus_2_capped_12' };
  }

  if (mapped.action === 'bounce') {
    if (state.bounceScored) return { score: 0, scoringRule: 'additional_bounce_zero_score' };
    return { score: -10, scoringRule: 'first_bounce_minus_10' };
  }

  if (mapped.action === 'unsub') {
    if (state.unsubScored) return { score: 0, scoringRule: 'additional_unsub_zero_score' };
    return { score: -20, scoringRule: 'first_unsub_minus_20' };
  }

  if (mapped.action === 'abuse') {
    if (state.abuseScored) return { score: 0, scoringRule: 'additional_abuse_zero_score' };
    return { score: -30, scoringRule: 'first_abuse_minus_30' };
  }

  return { score: 0, scoringRule: 'unsupported_zero_score' };
}

export function applyMailchimpScoreToState(
  mapped: MappedMailchimpActivity,
  score: number,
  state: MailchimpScoringState,
): void {
  if (mapped.action === 'open' && score > 0) {
    state.openScored = true;
  } else if (mapped.action === 'click' && score > 0) {
    state.scoredClickUrls.add(mapped.url ?? '__unknown_url__');
    state.clickScoreTotal += score;
  } else if (mapped.action === 'bounce' && score < 0) {
    state.bounceScored = true;
  } else if (mapped.action === 'unsub' && score < 0) {
    state.unsubScored = true;
  } else if (mapped.action === 'abuse' && score < 0) {
    state.abuseScored = true;
  }
}

function stableJson(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => stableJson(item)).join(',')}]`;
  }
  if (value && typeof value === 'object') {
    return `{${Object.entries(value as Record<string, unknown>)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, entry]) => `${JSON.stringify(key)}:${stableJson(entry)}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

async function shortSha256(input: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return Array.from(new Uint8Array(digest))
    .slice(0, 8)
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export async function buildMailchimpEngagementExternalId(input: {
  campaignId: string;
  email: string;
  emailId?: string | null;
  action: string;
  timestamp: string;
  url?: string | null;
  activity?: MailchimpActivityItem | null;
}): Promise<string> {
  const recipient = input.emailId?.trim() || normalizeMailchimpEmail(input.email);
  const urlOrActivityHash = input.url
    ? encodeURIComponent(input.url)
    : `hash-${await shortSha256(stableJson({
      action: input.action,
      timestamp: input.timestamp,
      url: input.url ?? null,
      ip: input.activity?.ip ?? null,
      raw_activity: input.activity ?? null,
    }))}`;

  return [
    'mailchimp',
    encodeURIComponent(input.campaignId),
    encodeURIComponent(recipient),
    encodeURIComponent(input.action),
    encodeURIComponent(input.timestamp),
    urlOrActivityHash,
  ].join(':');
}

async function fetchMailchimpEmailActivityPage(
  campaignId: string,
  count: number,
  offset: number,
): Promise<MailchimpEmailActivityResponse> {
  return await mailchimpFetch<MailchimpEmailActivityResponse>(
    `/reports/${encodeURIComponent(campaignId)}/email-activity?count=${count}&offset=${offset}`,
  );
}

export async function fetchAllMailchimpEmailActivity(
  campaignId: string,
  maxEmails = 10000,
): Promise<MailchimpEmailActivity[]> {
  const emails: MailchimpEmailActivity[] = [];
  const pageSize = 1000;
  let offset = 0;

  while (emails.length < maxEmails) {
    const count = Math.min(pageSize, maxEmails - emails.length);
    const page = await fetchMailchimpEmailActivityPage(campaignId, count, offset);
    const batch = page.emails ?? [];
    emails.push(...batch);

    if (batch.length < count) break;
    offset += batch.length;
  }

  return emails;
}

async function ensureMailchimpCampaign(
  supabase: SupabaseClient,
  newsletter: MailchimpNewsletterForEngagement,
  dryRun: boolean,
): Promise<MailchimpCampaignBridge> {
  if (newsletter.campaign_id) {
    return {
      campaignId: newsletter.campaign_id,
      scoringKey: newsletter.campaign_id,
    };
  }

  const { data: existing, error: existingError } = await supabase
    .from('campaigns')
    .select('id')
    .eq('provider', 'mailchimp')
    .eq('external_id', newsletter.mailchimp_campaign_id)
    .maybeSingle();

  if (existingError) {
    throw new Error(`Failed to load Mailchimp campaign bridge: ${existingError.message}`);
  }

  if (existing?.id) {
    if (!dryRun) {
      const { error: linkError } = await supabase
        .from('mailchimp_newsletters')
        .update({ campaign_id: existing.id, updated_at: new Date().toISOString() })
        .eq('id', newsletter.id);
      if (linkError) throw new Error(`Failed to link Mailchimp newsletter to campaign: ${linkError.message}`);
    }
    return {
      campaignId: existing.id,
      scoringKey: existing.id,
    };
  }

  if (dryRun) {
    return {
      campaignId: null,
      scoringKey: `dry-run:${newsletter.mailchimp_campaign_id}`,
    };
  }

  const { data: inserted, error: insertError } = await supabase
    .from('campaigns')
    .insert({
      name: newsletter.title || newsletter.subject || `Mailchimp ${newsletter.mailchimp_campaign_id}`,
      subject: newsletter.subject,
      provider: 'mailchimp',
      external_id: newsletter.mailchimp_campaign_id,
      sent_at: newsletter.sent_at ?? null,
      updated_at: new Date().toISOString(),
    })
    .select('id')
    .single();

  if (insertError || !inserted?.id) {
    if ((insertError as { code?: string } | null)?.code === '23505') {
      const { data: raced } = await supabase
        .from('campaigns')
        .select('id')
        .eq('provider', 'mailchimp')
        .eq('external_id', newsletter.mailchimp_campaign_id)
        .maybeSingle();
      if (raced?.id) {
        const { error: linkError } = await supabase
          .from('mailchimp_newsletters')
          .update({ campaign_id: raced.id, updated_at: new Date().toISOString() })
          .eq('id', newsletter.id);
        if (linkError) throw new Error(`Failed to link Mailchimp newsletter to raced campaign bridge: ${linkError.message}`);
        return {
          campaignId: raced.id,
          scoringKey: raced.id,
        };
      }
    }
    throw new Error(`Failed to create Mailchimp campaign bridge: ${insertError?.message}`);
  }

  const { error: updateError } = await supabase
    .from('mailchimp_newsletters')
    .update({ campaign_id: inserted.id, updated_at: new Date().toISOString() })
    .eq('id', newsletter.id);
  if (updateError) throw new Error(`Failed to link Mailchimp newsletter to campaign: ${updateError.message}`);

  return {
    campaignId: inserted.id,
    scoringKey: inserted.id,
  };
}

export async function resolveMailchimpContactBatch(
  supabase: SupabaseClient,
  rows: Array<{ email: string; listId: string | null }>,
): Promise<Map<string, string>> {
  const result = new Map<string, string>();
  const emailsByList = new Map<string, Set<string>>();
  const allEmails = new Set<string>();

  for (const row of rows) {
    const email = normalizeMailchimpEmail(row.email);
    if (!email) continue;
    allEmails.add(email);
    if (!row.listId) continue;
    const existing = emailsByList.get(row.listId) ?? new Set<string>();
    existing.add(email);
    emailsByList.set(row.listId, existing);
  }

  for (const [listId, emails] of emailsByList.entries()) {
    const emailList = [...emails];
    if (emailList.length === 0) continue;

    const { data, error } = await supabase
      .from('mailchimp_contact_links')
      .select('contact_id, email_address')
      .eq('list_id', listId)
      .in('email_address', emailList);

    if (error) {
      throw new Error(`Failed to batch resolve Mailchimp contact links: ${error.message}`);
    }

    for (const link of (data ?? []) as Array<{ contact_id?: string; email_address?: string }>) {
      const email = normalizeMailchimpEmail(link.email_address);
      if (email && link.contact_id) result.set(email, link.contact_id);
    }
  }

  const remainingEmails = [...allEmails].filter((email) => !result.has(email));
  if (remainingEmails.length === 0) return result;

  const { data: contacts, error: contactError } = await supabase
    .from('contacts')
    .select('id, email')
    .in('email', remainingEmails);

  if (contactError) {
    throw new Error(`Failed to batch resolve contacts by email: ${contactError.message}`);
  }

  for (const contact of (contacts ?? []) as Array<{ id?: string; email?: string }>) {
    const email = normalizeMailchimpEmail(contact.email);
    if (email && contact.id && !result.has(email)) result.set(email, contact.id);
  }

  return result;
}

async function eventExists(supabase: SupabaseClient, externalId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from('campaign_events')
    .select('id')
    .eq('external_id', externalId)
    .maybeSingle();

  if (error) throw new Error(`Failed to check existing Mailchimp event: ${error.message}`);
  return Boolean(data?.id);
}

async function loadScoringState(
  supabase: SupabaseClient,
  campaignId: string,
  contactId: string,
): Promise<MailchimpScoringState> {
  const state = createEmptyMailchimpScoringState();
  const { data, error } = await supabase
    .from('campaign_events')
    .select('event_type, score, source')
    .eq('campaign_id', campaignId)
    .eq('contact_id', contactId);

  if (error) throw new Error(`Failed to load Mailchimp scoring state: ${error.message}`);

  for (const event of (data ?? []) as Array<{ event_type?: string; score?: number; source?: Record<string, unknown> }>) {
    if (event.source?.provider !== 'mailchimp') continue;
    const action = String(event.source?.action ?? '');
    if (event.event_type === 'opened' && (event.score ?? 0) > 0) {
      state.openScored = true;
    }
    if (event.event_type === 'clicked' && (event.score ?? 0) > 0) {
      state.clickScoreTotal += event.score ?? 0;
      state.scoredClickUrls.add(String(event.source?.url ?? '__unknown_url__'));
    }
    if (event.event_type === 'bounced' && (event.score ?? 0) < 0) {
      state.bounceScored = true;
    }
    if (action === 'unsub' && (event.score ?? 0) < 0) {
      state.unsubScored = true;
    }
    if (action === 'abuse' && (event.score ?? 0) < 0) {
      state.abuseScored = true;
    }
  }

  return state;
}

async function updateCampaignSummary(
  supabase: SupabaseClient,
  input: {
    campaignId: string;
    contactId: string;
    email: string;
    eventType: CampaignEventType;
    scoreDelta: number;
    eventTimestamp: string;
    isUniqueClickScore: boolean;
  },
): Promise<void> {
  const { data: existing, error: fetchError } = await supabase
    .from('campaign_contact_summary')
    .select('*')
    .eq('campaign_id', input.campaignId)
    .eq('contact_id', input.contactId)
    .maybeSingle();

  if (fetchError) throw new Error(`Failed to load campaign summary: ${fetchError.message}`);

  const base = existing ?? {};
  const emailsSent = Number(base.emails_sent ?? 0) + (input.eventType === 'sent' ? 1 : 0);
  const emailsOpened = Number(base.emails_opened ?? 0) + (input.eventType === 'opened' ? 1 : 0);
  const emailsClicked = Number(base.emails_clicked ?? 0) + (input.eventType === 'clicked' ? 1 : 0);
  const emailsBounced = Number(base.emails_bounced ?? 0) + (input.eventType === 'bounced' ? 1 : 0);
  const uniqueClicks = Number(base.unique_clicks ?? 0) + (input.eventType === 'clicked' && input.isUniqueClickScore ? 1 : 0);

  let firstOpenedAt = base.first_opened_at ?? null;
  let lastOpenedAt = base.last_opened_at ?? null;
  let firstClickedAt = base.first_clicked_at ?? null;
  let lastClickedAt = base.last_clicked_at ?? null;

  if (input.eventType === 'opened') {
    firstOpenedAt = firstOpenedAt ?? input.eventTimestamp;
    lastOpenedAt = input.eventTimestamp;
  }

  if (input.eventType === 'clicked') {
    firstClickedAt = firstClickedAt ?? input.eventTimestamp;
    lastClickedAt = input.eventTimestamp;
  }

  const payload = {
    email: input.email,
    total_score: Number(base.total_score ?? 0) + input.scoreDelta,
    opened: emailsOpened > 0,
    clicked: emailsClicked > 0,
    converted: Boolean(base.converted ?? false),
    first_event_at: base.first_event_at ?? input.eventTimestamp,
    last_event_at: input.eventTimestamp,
    emails_sent: emailsSent,
    emails_delivered: Number(base.emails_delivered ?? 0),
    emails_opened: emailsOpened,
    emails_clicked: emailsClicked,
    emails_bounced: emailsBounced,
    emails_replied: Number(base.emails_replied ?? 0),
    unique_clicks: uniqueClicks,
    first_opened_at: firstOpenedAt,
    last_opened_at: lastOpenedAt,
    first_clicked_at: firstClickedAt,
    last_clicked_at: lastClickedAt,
    workflow_emails_sent: Number(base.workflow_emails_sent ?? 0),
    workflow_emails_opened: Number(base.workflow_emails_opened ?? 0),
    workflow_emails_clicked: Number(base.workflow_emails_clicked ?? 0),
  };

  if (existing) {
    const { error } = await supabase
      .from('campaign_contact_summary')
      .update(payload)
      .eq('campaign_id', input.campaignId)
      .eq('contact_id', input.contactId);
    if (error) throw new Error(`Failed to update campaign summary: ${error.message}`);
    return;
  }

  const { error } = await supabase
    .from('campaign_contact_summary')
    .insert({
      campaign_id: input.campaignId,
      contact_id: input.contactId,
      ...payload,
    });
  if (error) throw new Error(`Failed to insert campaign summary: ${error.message}`);
}

async function insertCampaignEvent(
  supabase: SupabaseClient,
  input: {
    campaignId: string;
    contactId: string;
    email: string;
    mapped: MappedMailchimpActivity;
    score: MailchimpActivityScore;
    externalId: string;
    newsletter: MailchimpNewsletterForEngagement;
    listId: string | null;
    rawActivity: MailchimpActivityItem;
    dryRun: boolean;
  },
): Promise<'inserted' | 'skipped_existing'> {
  if (await eventExists(supabase, input.externalId)) {
    return 'skipped_existing';
  }

  if (input.dryRun) return 'inserted';

  const { error } = await supabase.from('campaign_events').insert({
    campaign_id: input.campaignId,
    contact_id: input.contactId,
    email: input.email,
    event_type: input.mapped.eventType,
    event_timestamp: input.mapped.timestamp,
    score: input.score.score,
    external_id: input.externalId,
    source: {
      provider: 'mailchimp',
      mailchimp_campaign_id: input.newsletter.mailchimp_campaign_id,
      mailchimp_newsletter_id: input.newsletter.id,
      list_id: input.listId,
      email: input.email,
      action: input.mapped.action,
      url: input.mapped.url,
      scoring_rule: input.score.scoringRule,
      raw_activity: input.rawActivity,
    },
  });

  if ((error as { code?: string } | null)?.code === '23505') return 'skipped_existing';
  if (error) throw new Error(`Failed to insert Mailchimp campaign event: ${error.message}`);
  return 'inserted';
}

export async function syncMailchimpEngagementForNewsletters(
  supabase: SupabaseClient,
  newsletters: MailchimpNewsletterForEngagement[],
  options: MailchimpEngagementSyncOptions = {},
): Promise<MailchimpEngagementStats> {
  const stats: MailchimpEngagementStats = {
    campaigns_scanned: 0,
    activities_scanned: 0,
    events_inserted: 0,
    events_skipped_existing: 0,
    contacts_matched: 0,
    contacts_missing: 0,
    summaries_updated: 0,
    errors: [],
  };

  const stateCache = new Map<string, MailchimpScoringState>();
  const matchedRecipients = new Set<string>();
  const missingRecipients = new Set<string>();

  for (const newsletter of newsletters) {
    try {
      stats.campaigns_scanned += 1;
      const bridge = await ensureMailchimpCampaign(supabase, newsletter, Boolean(options.dryRun));
      const maxEmails = Math.max(1, options.maxEmailsPerCampaign ?? 10000);
      const pageSize = 1000;
      let offset = 0;
      let processedEmails = 0;
      const fetchPage = options.fetchEmailActivityPage ?? fetchMailchimpEmailActivityPage;

      while (processedEmails < maxEmails) {
        const count = Math.min(pageSize, maxEmails - processedEmails);
        const page = await fetchPage(newsletter.mailchimp_campaign_id, count, offset);
        const rawRows = page.emails ?? [];
        if (rawRows.length === 0) break;

        const preparedRows: PreparedMailchimpActivityRow[] = rawRows
          .map((row) => {
            const email = normalizeMailchimpEmail(row.email_address);
            if (!email) return null;

            const mappedActivities = (row.activity ?? [])
              .map((activity) => ({ activity, mapped: mapMailchimpActivity(activity) }))
              .filter((item): item is MailchimpActivityWithMapping => Boolean(item.mapped));

            stats.activities_scanned += mappedActivities.length;
            if (mappedActivities.length === 0) return null;

            return {
              email,
              emailId: row.email_id?.trim() || null,
              listId: row.list_id ?? newsletter.audience_id ?? null,
              mappedActivities,
            };
          })
          .filter((row): row is PreparedMailchimpActivityRow => Boolean(row));

        let contactIdsByEmail: Map<string, string>;
        try {
          contactIdsByEmail = await resolveMailchimpContactBatch(supabase, preparedRows);
        } catch (error) {
          stats.errors.push({
            campaign_id: newsletter.mailchimp_campaign_id,
            message: error instanceof Error ? error.message : 'Failed to batch resolve contacts',
          });
          processedEmails += rawRows.length;
          offset += rawRows.length;
          if (rawRows.length < count) break;
          continue;
        }

        for (const row of preparedRows) {
          const contactId = contactIdsByEmail.get(row.email) ?? null;
          const recipientKey = `${row.listId ?? ''}:${row.email}`;

          if (!contactId) {
            if (!missingRecipients.has(recipientKey)) {
              missingRecipients.add(recipientKey);
              stats.contacts_missing += 1;
            }
            continue;
          }

          if (!matchedRecipients.has(recipientKey)) {
            matchedRecipients.add(recipientKey);
            stats.contacts_matched += 1;
          }

          const stateKey = `${bridge.scoringKey}:${contactId}`;
          let scoringState = stateCache.get(stateKey);
          if (!scoringState) {
            scoringState = bridge.campaignId
              ? await loadScoringState(supabase, bridge.campaignId, contactId)
              : createEmptyMailchimpScoringState();
            stateCache.set(stateKey, scoringState);
          }

          for (const { activity, mapped } of row.mappedActivities) {
            const score = scoreMailchimpActivity(mapped, scoringState);
            const externalId = await buildMailchimpEngagementExternalId({
              campaignId: newsletter.mailchimp_campaign_id,
              email: row.email,
              emailId: row.emailId,
              action: mapped.action,
              timestamp: mapped.timestamp,
              url: mapped.url,
              activity,
            });

            try {
              const status = await insertCampaignEvent(supabase, {
                campaignId: bridge.campaignId ?? '00000000-0000-0000-0000-000000000000',
                contactId,
                email: row.email,
                mapped,
                score,
                externalId,
                newsletter,
                listId: row.listId,
                rawActivity: activity,
                dryRun: Boolean(options.dryRun),
              });

              if (status === 'skipped_existing') {
                stats.events_skipped_existing += 1;
                continue;
              }

              stats.events_inserted += 1;
              applyMailchimpScoreToState(mapped, score.score, scoringState);

              if (!options.dryRun && bridge.campaignId) {
                await updateCampaignSummary(supabase, {
                  campaignId: bridge.campaignId,
                  contactId,
                  email: row.email,
                  eventType: mapped.eventType,
                  scoreDelta: score.score,
                  eventTimestamp: mapped.timestamp,
                  isUniqueClickScore: mapped.eventType === 'clicked' && score.score > 0,
                });
                stats.summaries_updated += 1;
              }
            } catch (error) {
              stats.errors.push({
                campaign_id: newsletter.mailchimp_campaign_id,
                email: row.email,
                message: error instanceof Error ? error.message : 'Failed to process activity',
              });
            }
          }
        }

        processedEmails += rawRows.length;
        offset += rawRows.length;
        if (rawRows.length < count) break;
      }
    } catch (error) {
      stats.errors.push({
        campaign_id: newsletter.mailchimp_campaign_id,
        message: error instanceof Error ? error.message : 'Failed to sync campaign engagement',
      });
    }
  }

  return stats;
}
