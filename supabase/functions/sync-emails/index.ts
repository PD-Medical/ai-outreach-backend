/**
 * Sync Emails Edge Function
 * 
 * Triggered by pg_cron every 1 minute
 * Fetches new emails from all active mailboxes and imports them
 * 
 * Deploy: supabase functions deploy sync-emails
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

// Import shared utilities
import { withDenoImapClient } from '../_shared/email/deno-imap-client.ts';
import { createThreadId } from '../_shared/email/thread-builder.ts';
import { parseImapMessages, shouldImportEmail } from '../_shared/email/email-parser.ts';
import {
  importEmails,
  getLastSyncedUid,
  updateMailboxSyncStatus
} from '../_shared/email/db-operations.ts';
import { Mailbox, SyncResult, ImapConfig } from '../_shared/email/types.ts';

// Configuration from environment variables
// EXTREMELY conservative batch size due to CPU limits (2s hard limit)
// Large emails (>100KB) cause CPU timeout even when fetching 1-2 emails
// Sync will be VERY slow but reliable - processes 1 email per minute per mailbox
// Use import-legacy-emails for bulk imports
const SYNC_BATCH_SIZE = parseInt(Deno.env.get('SYNC_BATCH_SIZE') || '1', 10);
const SYNC_TIMEOUT_MS = parseInt(Deno.env.get('SYNC_TIMEOUT_MS') || '55000', 10);
// Process mailboxes sequentially to avoid CPU limits
const MAX_CONCURRENT_MAILBOXES = parseInt(Deno.env.get('MAX_CONCURRENT_MAILBOXES') || '1', 10);

/**
 * Sync a single mailbox
 */
async function syncMailbox(
  supabase: any,
  mailbox: Mailbox
): Promise<SyncResult> {
  const startTime = Date.now();
  const result: SyncResult = {
    success: false,
    mailbox_id: mailbox.id,
    mailbox_email: mailbox.email,
    folders_synced: [],
    emails_imported: 0,
    errors: [],
    sync_duration_ms: 0
  };

  try {
    console.log(`[Sync] Starting sync for ${mailbox.email}`);

    // Get IMAP password from secrets
    const password = Deno.env.get(`IMAP_PASSWORD_${mailbox.id.replace(/-/g, '_')}`);
    if (!password) {
      throw new Error(`IMAP password not found for mailbox ${mailbox.id}`);
    }

    // IMAP configuration
    const imapConfig: ImapConfig = {
      host: mailbox.imap_host,
      port: mailbox.imap_port,
      user: mailbox.imap_username || mailbox.email,
      password: password,
      tls: true,
      tlsOptions: { rejectUnauthorized: false }
    };

    // Folders to sync
    // Based on folder discovery, this IMAP server uses INBOX.* namespace
    const foldersToSync = ['INBOX', 'INBOX.Sent'];

    // Sync each folder
    for (const folder of foldersToSync) {
      try {
        console.log(`[Sync] Syncing folder: ${folder} for ${mailbox.email}`);

        // Get last synced UID
        const lastUid = await getLastSyncedUid(supabase, mailbox.id, folder);
        console.log(`[Sync] Last synced UID for ${folder}: ${lastUid}`);

        // Fetch new emails
        const imapMessages = await withDenoImapClient(imapConfig, async (client) => {
          return await client.fetchEmails({
            folder: folder,
            startUid: lastUid,
            limit: SYNC_BATCH_SIZE // Configurable via SYNC_BATCH_SIZE env var
          });
        });

        if (imapMessages.length === 0) {
          console.log(`[Sync] No new emails in ${folder}`);
          result.folders_synced.push(folder);
          continue;
        }

        console.log(`[Sync] Fetched ${imapMessages.length} new emails from ${folder}`);

        // Parse emails
        const parsedEmails = parseImapMessages(imapMessages, mailbox.email, folder);

        // Apply CC deduplication and create thread IDs
        const emailsToImport = parsedEmails
          .filter(email => shouldImportEmail(email, mailbox.email))
          .map(email => ({
            ...email,
            thread_id: createThreadId(email)
          }));

        console.log(`[Sync] ${emailsToImport.length} emails after CC deduplication`);

        if (emailsToImport.length > 0) {
          // Import emails
          const importResult = await importEmails(supabase, emailsToImport, mailbox.id);
          
          result.emails_imported += importResult.imported;
          
          console.log(`[Sync] Imported ${importResult.imported} emails, skipped ${importResult.skipped}, errors ${importResult.errors}`);

          // Update last synced UID
          const highestUid = Math.max(...imapMessages.map(m => m.attributes.uid));
          await updateMailboxSyncStatus(supabase, mailbox.id, folder, highestUid, true);
        }

        result.folders_synced.push(folder);
      } catch (folderError) {
        const errorMsg = `Failed to sync folder ${folder}: ${folderError.message}`;
        console.error(`[Sync] ${errorMsg}`);
        result.errors.push(errorMsg);
        
        // Update sync status with error
        await updateMailboxSyncStatus(
          supabase,
          mailbox.id,
          folder,
          await getLastSyncedUid(supabase, mailbox.id, folder),
          false,
          errorMsg
        );
      }
    }

    result.success = result.errors.length === 0;
    result.sync_duration_ms = Date.now() - startTime;

    console.log(`[Sync] Completed sync for ${mailbox.email}: ${result.emails_imported} emails imported`);

    return result;
  } catch (error) {
    result.success = false;
    result.errors.push(error.message);
    result.sync_duration_ms = Date.now() - startTime;

    console.error(`[Sync] Failed to sync mailbox ${mailbox.email}:`, error);

    return result;
  }
}

/**
 * Main handler
 */
serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  // Only allow POST requests
  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ success: false, error: 'Method not allowed' }),
      {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  }

  const startTime = Date.now();

  try {
    console.log('[Sync] Email sync triggered');

    // Create Supabase client with service role key
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Fetch all active mailboxes
    const { data: mailboxes, error: fetchError } = await supabase
      .from('mailboxes')
      .select('*')
      .eq('is_active', true);

    if (fetchError) {
      throw new Error(`Failed to fetch mailboxes: ${fetchError.message}`);
    }

    if (!mailboxes || mailboxes.length === 0) {
      console.log('[Sync] No active mailboxes found');
      return new Response(
        JSON.stringify({
          success: true,
          message: 'No active mailboxes to sync',
          mailboxes: 0,
          duration_ms: Date.now() - startTime
        }),
        {
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        }
      );
    }

    console.log(`[Sync] Found ${mailboxes.length} active mailbox(es)`);

    // Sync mailboxes in parallel (configurable via MAX_CONCURRENT_MAILBOXES env var)
    const results: SyncResult[] = [];

    for (let i = 0; i < mailboxes.length; i += MAX_CONCURRENT_MAILBOXES) {
      const batch = mailboxes.slice(i, i + MAX_CONCURRENT_MAILBOXES);
      const batchResults = await Promise.all(
        batch.map(mailbox => syncMailbox(supabase, mailbox))
      );
      results.push(...batchResults);
    }

    // Aggregate results
    const totalImported = results.reduce((sum, r) => sum + r.emails_imported, 0);
    const totalErrors = results.reduce((sum, r) => sum + r.errors.length, 0);
    const successfulSyncs = results.filter(r => r.success).length;

    const response = {
      success: true,
      message: `Synced ${mailboxes.length} mailbox(es)`,
      stats: {
        mailboxes_synced: mailboxes.length,
        successful_syncs: successfulSyncs,
        failed_syncs: mailboxes.length - successfulSyncs,
        total_emails_imported: totalImported,
        total_errors: totalErrors,
        duration_ms: Date.now() - startTime
      },
      results: results.map(r => ({
        mailbox_email: r.mailbox_email,
        success: r.success,
        emails_imported: r.emails_imported,
        folders_synced: r.folders_synced,
        errors: r.errors,
        duration_ms: r.sync_duration_ms
      }))
    };

    console.log('[Sync] Sync completed:', response.stats);

    return new Response(JSON.stringify(response), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });
  } catch (error) {
    console.error('[Sync] Sync failed:', error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        duration_ms: Date.now() - startTime
      }),
      {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      }
    );
  }
});

