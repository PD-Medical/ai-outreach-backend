/**
 * Import Legacy Emails Edge Function
 * 
 * Manual trigger for importing historical emails
 * Supports batch processing with resume capability to handle 60s timeout
 * 
 * Deploy: supabase functions deploy import-legacy-emails
 * 
 * Usage:
 * POST /functions/v1/import-legacy-emails
 * Body: {
 *   mailbox_id: "uuid",
 *   folders: ["INBOX", "Sent"],
 *   start_date: "2024-01-01",
 *   end_date: "2025-01-01",
 *   resume_token: "INBOX:5000:3" // optional
 * }
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

import { withDenoImapClient } from '../_shared/email/deno-imap-client.ts';
import { createThreadId } from '../_shared/email/thread-builder.ts';
import { parseImapMessages, shouldImportEmail } from '../_shared/email/email-parser.ts';
import {
  importEmails,
  updateMailboxSyncStatus
} from '../_shared/email/db-operations.ts';
import { BatchImportRequest, BatchImportResponse, ImapConfig } from '../_shared/email/types.ts';

// Configuration from environment variables
const BATCH_SIZE = parseInt(Deno.env.get('IMPORT_BATCH_SIZE') || '50', 10);
const MAX_DURATION_MS = parseInt(Deno.env.get('IMPORT_TIMEOUT_MS') || '55000', 10);

/**
 * Parse resume token
 * Format: "{folder}:{last_uid}:{batch_number}"
 */
function parseResumeToken(token: string | undefined): {
  folder: string | null;
  lastUid: number;
  batchNumber: number;
} {
  if (!token) {
    return { folder: null, lastUid: 0, batchNumber: 0 };
  }

  const parts = token.split(':');
  if (parts.length !== 3) {
    return { folder: null, lastUid: 0, batchNumber: 0 };
  }

  return {
    folder: parts[0],
    lastUid: parseInt(parts[1]) || 0,
    batchNumber: parseInt(parts[2]) || 0
  };
}

/**
 * Create resume token
 */
function createResumeToken(folder: string, lastUid: number, batchNumber: number): string {
  return `${folder}:${lastUid}:${batchNumber}`;
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
    // Parse request body
    const body: BatchImportRequest = await req.json();
    const { mailbox_id, folders = ['INBOX', 'Sent'], start_date, end_date, resume_token } = body;

    if (!mailbox_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'mailbox_id is required' }),
        {
          status: 400,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    console.log('[Import] Legacy import started for mailbox:', mailbox_id);

    // Create Supabase client
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Fetch mailbox
    const { data: mailbox, error: fetchError } = await supabase
      .from('mailboxes')
      .select('*')
      .eq('id', mailbox_id)
      .single();

    if (fetchError || !mailbox) {
      return new Response(
        JSON.stringify({ success: false, error: 'Mailbox not found' }),
        {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    // Get IMAP password
    const password = Deno.env.get(`IMAP_PASSWORD_${mailbox_id.replace(/-/g, '_')}`);
    if (!password) {
      return new Response(
        JSON.stringify({ success: false, error: 'IMAP password not configured' }),
        {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    // IMAP config
    const imapConfig: ImapConfig = {
      host: mailbox.imap_host,
      port: mailbox.imap_port,
      user: mailbox.imap_username || mailbox.email,
      password: password,
      tls: true,
      tlsOptions: { rejectUnauthorized: false }
    };

    // Parse resume token
    const { folder: resumeFolder, lastUid: resumeUid, batchNumber } = parseResumeToken(resume_token);

    // Determine starting folder
    let currentFolderIndex = 0;
    if (resumeFolder) {
      currentFolderIndex = folders.indexOf(resumeFolder);
      if (currentFolderIndex === -1) {
        currentFolderIndex = 0;
      }
    }

    const currentFolder = folders[currentFolderIndex];

    console.log(`[Import] Processing folder: ${currentFolder}, starting from UID: ${resumeUid}, batch: ${batchNumber + 1}`);

    // Parse dates
    const startDate = start_date ? new Date(start_date) : undefined;
    const endDate = end_date ? new Date(end_date) : undefined;

    // Fetch emails
    let totalProcessed = 0;
    let totalImported = 0;
    const errors: string[] = [];
    let completed = false;
    let nextResumeToken: string | undefined;

    const imapMessages = await withDenoImapClient(imapConfig, async (client) => {
      return await client.fetchEmails({
        folder: currentFolder,
        startUid: resumeUid,
        startDate,
        endDate,
        limit: BATCH_SIZE
      });
    });

    console.log(`[Import] Fetched ${imapMessages.length} emails from ${currentFolder}`);

    // Check if we're approaching timeout
    if (Date.now() - startTime > MAX_DURATION_MS) {
      console.log('[Import] Approaching timeout, stopping batch');
      
      if (imapMessages.length > 0) {
        const highestUid = Math.max(...imapMessages.map(m => m.attributes.uid));
        nextResumeToken = createResumeToken(currentFolder, highestUid, batchNumber + 1);
      } else {
        // Move to next folder
        if (currentFolderIndex + 1 < folders.length) {
          nextResumeToken = createResumeToken(folders[currentFolderIndex + 1], 0, 0);
        } else {
          completed = true;
        }
      }
    } else if (imapMessages.length > 0) {
      // Parse emails
      const parsedEmails = parseImapMessages(imapMessages, mailbox.email, currentFolder);

      // Apply CC deduplication and create thread IDs
      const emailsToImport = parsedEmails
        .filter(email => shouldImportEmail(email, mailbox.email))
        .map(email => ({
          ...email,
          thread_id: createThreadId(email)
        }));

      console.log(`[Import] ${emailsToImport.length} emails after CC deduplication`);

      // Import emails
      if (emailsToImport.length > 0) {
        const importResult = await importEmails(supabase, emailsToImport, mailbox_id);
        totalImported = importResult.imported;
        totalProcessed = emailsToImport.length;

        console.log(`[Import] Imported ${importResult.imported}, skipped ${importResult.skipped}, errors ${importResult.errors}`);
      }

      // Determine next resume token
      const highestUid = Math.max(...imapMessages.map(m => m.attributes.uid));

      if (imapMessages.length < BATCH_SIZE) {
        // Finished this folder, move to next
        if (currentFolderIndex + 1 < folders.length) {
          nextResumeToken = createResumeToken(folders[currentFolderIndex + 1], 0, 0);
          console.log(`[Import] Folder ${currentFolder} complete, moving to next folder`);
        } else {
          // All folders complete
          completed = true;
          console.log('[Import] All folders complete');
        }
      } else {
        // More emails in this folder
        nextResumeToken = createResumeToken(currentFolder, highestUid, batchNumber + 1);
      }

      // Update mailbox sync status with progress
      const syncStatus = mailbox.sync_status || {};
      syncStatus.legacy_import = {
        folder: currentFolder,
        last_uid: highestUid,
        total_processed: (syncStatus.legacy_import?.total_processed || 0) + totalProcessed,
        in_progress: !completed
      };

      // Update last_synced_uid so sync can pick up from here
      await updateMailboxSyncStatus(supabase, mailbox_id, currentFolder, highestUid, true);
      
      // If completed, mark legacy import as done
      if (completed) {
        syncStatus.legacy_import.completed_at = new Date().toISOString();
        syncStatus.legacy_import.in_progress = false;
      }
      
      // Also update sync_status for progress tracking
      await supabase
        .from('mailboxes')
        .update({
          sync_status: syncStatus,
          updated_at: new Date().toISOString()
        })
        .eq('id', mailbox_id);
    } else {
      // No emails in this folder, move to next
      if (currentFolderIndex + 1 < folders.length) {
        nextResumeToken = createResumeToken(folders[currentFolderIndex + 1], 0, 0);
      } else {
        completed = true;
      }
    }

    // Build response
    const response: BatchImportResponse = {
      completed,
      processed: totalProcessed,
      total_imported: totalImported,
      resume_token: completed ? undefined : nextResumeToken,
      next_folder: completed ? undefined : (nextResumeToken ? nextResumeToken.split(':')[0] : undefined),
      errors
    };

    console.log('[Import] Batch complete:', response);

    return new Response(JSON.stringify(response), {
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    });
  } catch (error) {
    console.error('[Import] Import failed:', error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        completed: false
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

