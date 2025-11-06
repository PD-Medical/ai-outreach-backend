/**
 * Database Operations for Email Sync
 * 
 * Handles all database CRUD operations for email synchronization
 * Logic ported from scripts/FINAL_SCHEMA_GUIDE.md (lines 264-406)
 */

import { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import {
  Contact,
  Organization,
  Conversation,
  Email,
  ParsedEmail,
  DatabaseError
} from './types.ts';
import { extractDomain, parseFullName } from './email-parser.ts';
import { normalizeSubject } from './thread-builder.ts';

/**
 * Get or create an organization from email domain
 * Based on FINAL_SCHEMA_GUIDE.md lines 303-329
 */
export async function getOrCreateOrganization(
  supabase: SupabaseClient,
  domain: string | null
): Promise<Organization> {
  if (!domain || domain === 'unknown.local') {
    domain = 'unknown.local';
  }

  // Try to find existing organization
  const { data: existing, error: findError } = await supabase
    .from('organizations')
    .select('*')
    .eq('domain', domain)
    .single();

  if (existing && !findError) {
    return existing as Organization;
  }

  // Create new organization
  const orgName = domain.replace(/\./g, ' ').replace(/\b\w/g, c => c.toUpperCase());

  const { data: newOrg, error: createError } = await supabase
    .from('organizations')
    .insert({
      name: orgName,
      domain: domain,
      status: 'active',
      created_at: new Date().toISOString()
    })
    .select()
    .single();

  if (createError) {
    throw new DatabaseError(`Failed to create organization: ${createError.message}`);
  }

  return newOrg as Organization;
}

/**
 * Get or create a contact from email address
 * Based on FINAL_SCHEMA_GUIDE.md lines 264-301
 */
export async function getOrCreateContact(
  supabase: SupabaseClient,
  email: string,
  name?: string
): Promise<Contact> {
  if (!email) {
    throw new DatabaseError('Email address is required for contact');
  }

  // Try to find existing contact
  const { data: existing, error: findError } = await supabase
    .from('contacts')
    .select('*')
    .eq('email', email.toLowerCase())
    .single();

  if (existing && !findError) {
    return existing as Contact;
  }

  // Parse name into first/last
  const { first_name, last_name } = parseFullName(name);

  // Create organization from email domain
  const domain = extractDomain(email);
  const org = await getOrCreateOrganization(supabase, domain);

  // Create new contact
  const { data: newContact, error: createError } = await supabase
    .from('contacts')
    .insert({
      email: email.toLowerCase(),
      first_name: first_name || undefined,
      last_name: last_name || undefined,
      organization_id: org.id,
      status: 'active',
      created_at: new Date().toISOString()
    })
    .select()
    .single();

  if (createError) {
    throw new DatabaseError(`Failed to create contact: ${createError.message}`);
  }

  return newContact as Contact;
}

/**
 * Get or create a conversation for a thread
 * Based on FINAL_SCHEMA_GUIDE.md lines 331-367
 */
export async function getOrCreateConversation(
  supabase: SupabaseClient,
  threadId: string,
  email: ParsedEmail,
  contact: Contact,
  mailboxId: string
): Promise<Conversation> {
  // Check if conversation exists for this thread
  const { data: existing, error: findError } = await supabase
    .from('conversations')
    .select('*')
    .eq('thread_id', threadId)
    .single();

  if (existing && !findError) {
    return existing as Conversation;
  }

  // Create new conversation
  const { data: newConversation, error: createError } = await supabase
    .from('conversations')
    .insert({
      thread_id: threadId,
      subject: normalizeSubject(email.subject),
      mailbox_id: mailboxId,
      organization_id: contact.organization_id,
      primary_contact_id: contact.id,
      email_count: 0, // Will be updated when email is inserted
      first_email_at: email.received_at,
      last_email_at: email.received_at,
      last_email_direction: email.direction,
      status: 'active',
      requires_response: email.direction === 'incoming',
      created_at: new Date().toISOString()
    })
    .select()
    .single();

  if (createError) {
    throw new DatabaseError(`Failed to create conversation: ${createError.message}`);
  }

  return newConversation as Conversation;
}

/**
 * Check if email already exists (by message_id or IMAP UID)
 */
export async function emailExists(
  supabase: SupabaseClient,
  messageId: string,
  mailboxId: string,
  folder: string,
  uid: number
): Promise<string | null> {
  // Check by message_id first
  if (messageId) {
    const { data, error } = await supabase
      .from('emails')
      .select('id')
      .eq('message_id', messageId)
      .single();

    if (data && !error) {
      return data.id;
    }
  }

  // Check by IMAP UID (mailbox + folder + uid combo)
  const { data, error } = await supabase
    .from('emails')
    .select('id')
    .eq('mailbox_id', mailboxId)
    .eq('imap_folder', folder)
    .eq('imap_uid', uid)
    .single();

  if (data && !error) {
    return data.id;
  }

  return null;
}

/**
 * Insert a new email into the database
 */
export async function insertEmail(
  supabase: SupabaseClient,
  email: ParsedEmail,
  mailboxId: string,
  conversationId: string,
  contactId: string,
  organizationId: string
): Promise<string> {
  // Determine if email needs parsing (large emails >100KB stored as raw)
  const needsParsing = email.body_plain && email.body_plain.length > 102400;
  
  const { data, error } = await supabase
    .from('emails')
    .insert({
      message_id: email.message_id || `synthetic-${email.imap_uid}-${Date.now()}`,
      thread_id: email.thread_id,
      conversation_id: conversationId,
      in_reply_to: email.in_reply_to,
      email_references: email.references,
      subject: email.subject,
      from_email: email.from_email,
      from_name: email.from_name,
      to_emails: email.to_emails,
      cc_emails: email.cc_emails,
      bcc_emails: [],
      body_html: email.body_html,
      body_plain: email.body_plain,
      mailbox_id: mailboxId,
      contact_id: contactId,
      organization_id: organizationId,
      direction: email.direction,
      is_seen: email.is_seen,
      is_flagged: email.is_flagged,
      is_answered: email.is_answered,
      is_draft: email.is_draft,
      is_deleted: email.is_deleted,
      imap_folder: email.imap_folder,
      imap_uid: email.imap_uid,
      headers: email.headers,
      attachments: email.attachments,
      sent_at: email.sent_at,
      received_at: email.received_at,
      needs_parsing: needsParsing,
      created_at: new Date().toISOString()
    })
    .select('id')
    .single();

  if (error) {
    throw new DatabaseError(`Failed to insert email: ${error.message}`);
  }

  return data.id;
}

/**
 * Update conversation statistics after adding an email
 * Based on FINAL_SCHEMA_GUIDE.md lines 369-406
 */
export async function updateConversationStats(
  supabase: SupabaseClient,
  conversationId: string
): Promise<void> {
  const { error } = await supabase.rpc('update_conversation_stats', {
    p_conversation_id: conversationId
  });

  if (error) {
    // If RPC doesn't exist, fall back to manual update
    const { data: emails } = await supabase
      .from('emails')
      .select('received_at, direction')
      .eq('conversation_id', conversationId)
      .order('received_at', { ascending: true });

    if (emails && emails.length > 0) {
      const lastEmail = emails[emails.length - 1];

      await supabase
        .from('conversations')
        .update({
          email_count: emails.length,
          first_email_at: emails[0].received_at,
          last_email_at: lastEmail.received_at,
          last_email_direction: lastEmail.direction,
          requires_response: lastEmail.direction === 'incoming',
          updated_at: new Date().toISOString()
        })
        .eq('id', conversationId);
    }
  }
}

/**
 * Update mailbox sync status after successful sync
 */
export async function updateMailboxSyncStatus(
  supabase: SupabaseClient,
  mailboxId: string,
  folder: string,
  lastUid: number,
  success: boolean = true,
  errorMessage?: string
): Promise<void> {
  // Get current sync data
  const { data: mailbox } = await supabase
    .from('mailboxes')
    .select('last_synced_uid, sync_status')
    .eq('id', mailboxId)
    .single();

  if (!mailbox) {
    throw new DatabaseError(`Mailbox ${mailboxId} not found`);
  }

  // Update last_synced_uid
  const lastSyncedUid = mailbox.last_synced_uid || {};
  lastSyncedUid[folder] = lastUid;

  // Update sync_status
  const syncStatus = mailbox.sync_status || {};
  syncStatus.last_sync_success = success;
  syncStatus.last_sync_timestamp = new Date().toISOString();
  if (errorMessage) {
    syncStatus.last_sync_error = errorMessage;
  } else {
    delete syncStatus.last_sync_error;
  }

  // Update mailbox
  const { error } = await supabase
    .from('mailboxes')
    .update({
      last_synced_uid: lastSyncedUid,
      sync_status: syncStatus,
      last_synced_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    })
    .eq('id', mailboxId);

  if (error) {
    throw new DatabaseError(`Failed to update mailbox sync status: ${error.message}`);
  }
}

/**
 * Get last synced UID for a folder
 */
export async function getLastSyncedUid(
  supabase: SupabaseClient,
  mailboxId: string,
  folder: string
): Promise<number> {
  const { data: mailbox, error } = await supabase
    .from('mailboxes')
    .select('last_synced_uid')
    .eq('id', mailboxId)
    .single();

  if (error || !mailbox) {
    return 0;
  }

  const lastSyncedUid = mailbox.last_synced_uid || {};
  return lastSyncedUid[folder] || 0;
}

/**
 * Complete email import workflow
 * This orchestrates all the steps: contact, org, conversation, email insert, stats update
 */
export async function importEmail(
  supabase: SupabaseClient,
  email: ParsedEmail,
  mailboxId: string
): Promise<{ emailId: string; created: boolean }> {
  // Check if email already exists
  const existingId = await emailExists(
    supabase,
    email.message_id,
    mailboxId,
    email.imap_folder,
    email.imap_uid
  );

  if (existingId) {
    return { emailId: existingId, created: false };
  }

  // Get or create contact
  const contact = await getOrCreateContact(
    supabase,
    email.from_email,
    email.from_name
  );

  // Get or create conversation
  const conversation = await getOrCreateConversation(
    supabase,
    email.thread_id,
    email,
    contact,
    mailboxId
  );

  // Insert email
  const emailId = await insertEmail(
    supabase,
    email,
    mailboxId,
    conversation.id,
    contact.id,
    contact.organization_id
  );

  // Update conversation stats
  await updateConversationStats(supabase, conversation.id);

  return { emailId, created: true };
}

/**
 * Batch import multiple emails
 */
export async function importEmails(
  supabase: SupabaseClient,
  emails: ParsedEmail[],
  mailboxId: string
): Promise<{
  imported: number;
  skipped: number;
  errors: number;
  emailIds: string[];
}> {
  const results = {
    imported: 0,
    skipped: 0,
    errors: 0,
    emailIds: [] as string[]
  };

  for (const email of emails) {
    try {
      const { emailId, created } = await importEmail(supabase, email, mailboxId);
      
      results.emailIds.push(emailId);
      
      if (created) {
        results.imported++;
      } else {
        results.skipped++;
      }
    } catch (error) {
      console.error(`[DB] Failed to import email:`, error);
      results.errors++;
    }
  }

  return results;
}


