import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

export interface MailchimpAudience {
  id: string;
  name: string;
  stats?: {
    member_count?: number;
    unsubscribe_count?: number;
    cleaned_count?: number;
  };
  campaign_defaults?: {
    from_name?: string;
    from_email?: string;
  };
}

interface MailchimpListsResponse {
  lists?: MailchimpAudience[];
}

export interface MailchimpMember {
  id: string;
  email_address: string;
  unique_email_id?: string;
  status: string;
  merge_fields?: Record<string, unknown>;
  tags?: Array<{ id?: number; name?: string }>;
  marketing_permissions?: unknown[];
  stats?: Record<string, unknown>;
  vip?: boolean;
  last_changed?: string;
}

interface MailchimpMembersResponse {
  members?: MailchimpMember[];
  total_items?: number;
}

export interface ExportCandidate {
  contact_id: string;
  email: string;
  subscriber_hash: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  status: string;
  tags: unknown;
  organization_name: string | null;
}

export interface SyncStats {
  scanned: number;
  created: number;
  updated: number;
  linked: number;
  skipped: number;
  errors: number;
  dry_run: boolean;
}

export interface NormalizedMailchimpName {
  firstName: string | null;
  lastName: string | null;
}

interface ExistingNameFields {
  first_name?: string | null;
  last_name?: string | null;
}

const TITLE_PREFIX_PATTERN = /^(dr|mr|mrs|ms|miss|prof|professor|a\/prof|assoc\.?\s+prof)\.?\s+/i;
const BRACKETED_HINT_PATTERN = /\s*[\(\[][^)\]]+[\)\]]\s*/g;

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

export async function mailchimpFetch<T>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const apiKey = getMailchimpApiKey();
  const response = await fetch(`${getMailchimpBaseUrl()}${path}`, {
    ...options,
    headers: {
      Authorization: `Basic ${btoa(`anystring:${apiKey}`)}`,
      'Content-Type': 'application/json',
      ...(options.headers ?? {}),
    },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Mailchimp API error ${response.status}: ${errorText}`);
  }

  return await response.json() as T;
}

async function mailchimpFetchOptional<T>(path: string): Promise<T | null> {
  const apiKey = getMailchimpApiKey();
  const response = await fetch(`${getMailchimpBaseUrl()}${path}`, {
    headers: {
      Authorization: `Basic ${btoa(`anystring:${apiKey}`)}`,
      'Content-Type': 'application/json',
    },
  });

  if (response.status === 404) return null;
  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Mailchimp API error ${response.status}: ${errorText}`);
  }
  return await response.json() as T;
}

export async function fetchMailchimpAudiences(): Promise<MailchimpAudience[]> {
  const data = await mailchimpFetch<MailchimpListsResponse>('/lists?count=100&sort_field=date_created&sort_dir=DESC');
  return data.lists ?? [];
}

export async function storeMailchimpAudiences(
  supabase: SupabaseClient,
  audiences: MailchimpAudience[],
): Promise<void> {
  if (audiences.length === 0) return;

  const { error } = await supabase
    .from('mailchimp_audiences')
    .upsert(audiences.map((audience) => ({
      list_id: audience.id,
      name: audience.name,
      member_count: audience.stats?.member_count ?? null,
      default_from_name: audience.campaign_defaults?.from_name ?? null,
      default_reply_to_email: audience.campaign_defaults?.from_email?.toLowerCase() ?? null,
      raw_payload: audience,
      last_synced_at: new Date().toISOString(),
    })), { onConflict: 'list_id' });

  if (error) {
    throw new Error(`Failed to store Mailchimp audiences: ${error.message}`);
  }
}

export async function fetchMailchimpMembers(
  listId: string,
  limit = 1000,
): Promise<MailchimpMember[]> {
  const members: MailchimpMember[] = [];
  const pageSize = 1000;
  let offset = 0;

  while (members.length < limit) {
    const count = Math.min(pageSize, limit - members.length);
    const page = await mailchimpFetch<MailchimpMembersResponse>(
      `/lists/${encodeURIComponent(listId)}/members?count=${count}&offset=${offset}`,
    );

    const batch = page.members ?? [];
    members.push(...batch);
    if (batch.length < count) break;
    offset += batch.length;
  }

  return members;
}

function normaliseEmail(email: string | null | undefined): string {
  return (email ?? '').trim().toLowerCase();
}

function localStatusFromMailchimp(status: string): string | null {
  if (status === 'unsubscribed') return 'unsubscribed';
  if (status === 'cleaned') return 'bounced';
  return null;
}

function prefixedTagNames(tags: MailchimpMember['tags'], prefix: string): string[] {
  return (tags ?? [])
    .map((tag) => tag.name?.trim())
    .filter((name): name is string => Boolean(name && name.startsWith(prefix)));
}

function candidateTagNames(tags: unknown, prefix: string): string[] {
  if (!Array.isArray(tags)) return [];
  return tags
    .map((tag) => {
      if (typeof tag === 'string') return tag.trim();
      if (tag && typeof tag === 'object' && 'name' in tag) {
        return String((tag as { name?: unknown }).name ?? '').trim();
      }
      return '';
    })
    .filter((tag) => tag.startsWith(prefix));
}

function memberMergeField(member: MailchimpMember, key: string): string | null {
  const value = member.merge_fields?.[key];
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function cleanMailchimpNamePart(value: string | null | undefined): string | null {
  const cleaned = (value ?? '')
    .replace(BRACKETED_HINT_PATTERN, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(TITLE_PREFIX_PATTERN, '')
    .replace(/\s+/g, ' ')
    .trim();

  return cleaned || null;
}

export function normalizeMailchimpMemberName(
  firstName: string | null | undefined,
  lastName: string | null | undefined,
): NormalizedMailchimpName {
  const cleanedFirst = cleanMailchimpNamePart(firstName);
  const cleanedLast = cleanMailchimpNamePart(lastName);

  if (!cleanedFirst) {
    return {
      firstName: null,
      lastName: cleanedLast,
    };
  }

  if (cleanedLast) {
    return {
      firstName: cleanedFirst,
      lastName: cleanedLast,
    };
  }

  const parts = cleanedFirst.split(' ').filter(Boolean);
  if (parts.length <= 1) {
    return {
      firstName: cleanedFirst,
      lastName: null,
    };
  }

  return {
    firstName: parts[0],
    lastName: parts.slice(1).join(' '),
  };
}

function hasText(value: string | null | undefined): boolean {
  return Boolean(value && value.trim());
}

export function namesForMailchimpImport(
  normalizedName: NormalizedMailchimpName,
  existing?: ExistingNameFields | null,
): NormalizedMailchimpName {
  if (!existing) return normalizedName;

  return {
    firstName: hasText(existing.first_name) ? null : normalizedName.firstName,
    lastName: hasText(existing.last_name) ? null : normalizedName.lastName,
  };
}

async function getTagPrefix(supabase: SupabaseClient): Promise<string> {
  const { data } = await supabase
    .from('system_config')
    .select('value')
    .eq('key', 'mailchimp_contact_sync_tag_prefix')
    .maybeSingle();
  return typeof data?.value === 'string' ? data.value : 'mc:';
}

async function upsertMailchimpContactLink(
  supabase: SupabaseClient,
  contactId: string,
  listId: string,
  member: MailchimpMember,
  direction: 'pulled' | 'pushed',
  tagPrefix: string,
): Promise<void> {
  const now = new Date().toISOString();
  const payload = {
    contact_id: contactId,
    list_id: listId,
    subscriber_hash: member.id,
    unique_email_id: member.unique_email_id ?? null,
    email_address: normaliseEmail(member.email_address),
    status: member.status,
    merge_fields: member.merge_fields ?? {},
    mc_tags: prefixedTagNames(member.tags, tagPrefix),
    marketing_permissions: member.marketing_permissions ?? [],
    stats: member.stats ?? {},
    vip: Boolean(member.vip),
    last_changed_remote: member.last_changed ?? null,
    last_pulled_at: direction === 'pulled' ? now : undefined,
    last_pushed_at: direction === 'pushed' ? now : undefined,
    raw_payload: member,
  };

  const { error } = await supabase
    .from('mailchimp_contact_links')
    .upsert(payload, { onConflict: 'contact_id,list_id' });

  if (error) {
    throw new Error(`Failed to upsert Mailchimp contact link: ${error.message}`);
  }
}

async function updateLocalComplianceStatus(
  supabase: SupabaseClient,
  contactId: string,
  mailchimpStatus: string,
): Promise<void> {
  const status = localStatusFromMailchimp(mailchimpStatus);
  if (!status) return;

  const { error } = await supabase
    .from('contacts')
    .update({ status, updated_at: new Date().toISOString() })
    .eq('id', contactId);

  if (error) {
    throw new Error(`Failed to update local contact status: ${error.message}`);
  }
}

export async function importMailchimpContacts(
  supabase: SupabaseClient,
  options: { listId: string; limit?: number; dryRun?: boolean },
): Promise<SyncStats> {
  const limit = Math.max(1, Math.min(options.limit ?? 1000, 10000));
  const tagPrefix = await getTagPrefix(supabase);
  const members = await fetchMailchimpMembers(options.listId, limit);
  const stats: SyncStats = {
    scanned: members.length,
    created: 0,
    updated: 0,
    linked: 0,
    skipped: 0,
    errors: 0,
    dry_run: Boolean(options.dryRun),
  };

  if (options.dryRun) return stats;

  for (const member of members) {
    const email = normaliseEmail(member.email_address);
    if (!email) {
      stats.skipped += 1;
      continue;
    }

    try {
      const { data: existing } = await supabase
        .from('contacts')
        .select('id, first_name, last_name')
        .eq('email', email)
        .maybeSingle();
      const normalizedName = normalizeMailchimpMemberName(
        memberMergeField(member, 'FNAME'),
        memberMergeField(member, 'LNAME'),
      );
      const importName = namesForMailchimpImport(normalizedName, existing);

      const { data, error } = await supabase.rpc('upsert_contact_with_org_v2', {
        p_email: email,
        p_first_name: importName.firstName,
        p_last_name: importName.lastName,
        p_job_title: null,
        p_role: null,
        p_phone: memberMergeField(member, 'PHONE'),
        p_department: null,
        p_facility_hint: null,
        p_signature_org_name: null,
        p_source: 'mailchimp',
        p_source_confidence: 0.7,
        p_contact_type: null,
      });

      if (error) throw error;
      const result = Array.isArray(data) ? data[0] : data;
      const contactId = result?.contact_id;
      if (!contactId) {
        stats.skipped += 1;
        continue;
      }

      await updateLocalComplianceStatus(supabase, contactId, member.status);
      await upsertMailchimpContactLink(supabase, contactId, options.listId, member, 'pulled', tagPrefix);
      stats.linked += 1;
      if (existing?.id) stats.updated += 1;
      else stats.created += 1;
    } catch (error) {
      console.error('[MailchimpContactImport] member failed:', email, error);
      stats.errors += 1;
    }
  }

  return stats;
}

export async function getExportPreview(
  supabase: SupabaseClient,
  listId: string,
): Promise<Record<string, unknown>> {
  const { data, error } = await supabase.rpc('mailchimp_export_preview', {
    p_list_id: listId,
  });
  if (error) throw new Error(`Failed to compute export preview: ${error.message}`);
  return data as Record<string, unknown>;
}

export async function exportMailchimpContacts(
  supabase: SupabaseClient,
  options: { listId: string; limit?: number; dryRun?: boolean },
): Promise<SyncStats> {
  const limit = Math.max(1, Math.min(options.limit ?? 100, 1000));
  const tagPrefix = await getTagPrefix(supabase);
  const { data, error } = await supabase.rpc('mailchimp_export_candidates', {
    p_list_id: options.listId,
    p_limit: limit,
  });
  if (error) throw new Error(`Failed to load Mailchimp export candidates: ${error.message}`);

  const candidates = (data ?? []) as ExportCandidate[];
  const stats: SyncStats = {
    scanned: candidates.length,
    created: 0,
    updated: 0,
    linked: 0,
    skipped: 0,
    errors: 0,
    dry_run: Boolean(options.dryRun),
  };

  if (options.dryRun) return stats;

  for (const candidate of candidates) {
    try {
      const existing = await mailchimpFetchOptional<MailchimpMember>(
        `/lists/${encodeURIComponent(options.listId)}/members/${candidate.subscriber_hash}`,
      );

      if (existing?.status === 'unsubscribed' || existing?.status === 'cleaned') {
        await updateLocalComplianceStatus(supabase, candidate.contact_id, existing.status);
        await upsertMailchimpContactLink(supabase, candidate.contact_id, options.listId, existing, 'pulled', tagPrefix);
        stats.skipped += 1;
        continue;
      }

      const mergeFields = {
        FNAME: candidate.first_name ?? '',
        LNAME: candidate.last_name ?? '',
        PHONE: candidate.phone ?? '',
        ORG: candidate.organization_name ?? '',
      };

      const body = existing
        ? { merge_fields: mergeFields }
        : {
          email_address: candidate.email,
          status_if_new: 'subscribed',
          merge_fields: mergeFields,
        };

      const member = existing
        ? await mailchimpFetch<MailchimpMember>(
          `/lists/${encodeURIComponent(options.listId)}/members/${candidate.subscriber_hash}`,
          { method: 'PATCH', body: JSON.stringify(body) },
        )
        : await mailchimpFetch<MailchimpMember>(
          `/lists/${encodeURIComponent(options.listId)}/members/${candidate.subscriber_hash}`,
          { method: 'PUT', body: JSON.stringify(body) },
        );

      const tags = candidateTagNames(candidate.tags, tagPrefix);
      if (tags.length > 0) {
        await mailchimpFetch(
          `/lists/${encodeURIComponent(options.listId)}/members/${candidate.subscriber_hash}/tags`,
          {
            method: 'POST',
            body: JSON.stringify({
              tags: tags.map((name) => ({ name, status: 'active' })),
            }),
          },
        );
      }

      await upsertMailchimpContactLink(supabase, candidate.contact_id, options.listId, member, 'pushed', tagPrefix);
      stats.linked += 1;
      if (existing) stats.updated += 1;
      else stats.created += 1;
    } catch (error) {
      console.error('[MailchimpContactExport] candidate failed:', candidate.email, error);
      stats.errors += 1;
    }
  }

  return stats;
}

export async function createSyncRun(
  supabase: SupabaseClient,
  params: { action: 'import' | 'export' | 'sync'; listId: string; requestedBy?: string | null; dryRun?: boolean },
): Promise<string | null> {
  if (params.dryRun) return null;

  const { data, error } = await supabase
    .from('mailchimp_contact_sync_runs')
    .insert({
      action: params.action,
      list_id: params.listId,
      status: 'running',
      requested_by: params.requestedBy === 'service-role' ? null : params.requestedBy ?? null,
      stats: {},
    })
    .select('id')
    .single();

  if (error) throw new Error(`Failed to create Mailchimp sync run: ${error.message}`);
  return data?.id ?? null;
}

export async function completeSyncRun(
  supabase: SupabaseClient,
  runId: string | null,
  status: 'completed' | 'failed',
  stats: Record<string, unknown>,
  error?: string,
): Promise<void> {
  if (!runId) return;

  await supabase
    .from('mailchimp_contact_sync_runs')
    .update({
      status,
      stats,
      error: error ?? null,
      completed_at: new Date().toISOString(),
    })
    .eq('id', runId);
}
