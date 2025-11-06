import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';
import { corsHeaders } from '../_shared/cors.ts';
import { withDenoImapClient } from '../_shared/email/deno-imap-client.ts';

interface RequestBody {
  mailbox_id?: string;
  email?: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    console.log('[ListFolders] Starting folder discovery');

    // Parse request body
    const body: RequestBody = await req.json().catch(() => ({}));
    const { mailbox_id, email } = body;

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Get mailbox to check
    let query = supabase
      .from('mailboxes')
      .select('*')
      .eq('is_active', true);

    if (mailbox_id) {
      query = query.eq('id', mailbox_id);
    } else if (email) {
      query = query.eq('email', email);
    }

    const { data: mailboxes, error: mailboxError } = await query;

    if (mailboxError) {
      throw new Error(`Failed to fetch mailboxes: ${mailboxError.message}`);
    }

    if (!mailboxes || mailboxes.length === 0) {
      return new Response(
        JSON.stringify({ error: 'No mailboxes found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    const results = [];

    // Check folders for each mailbox
    for (const mailbox of mailboxes) {
      console.log(`[ListFolders] Checking folders for ${mailbox.email}`);

      try {
        // Get IMAP password from environment
        const passwordKey = `IMAP_PASSWORD_${mailbox.id.replace(/-/g, '_')}`;
        const password = Deno.env.get(passwordKey);

        if (!password) {
          console.log(`[ListFolders] No password configured for ${mailbox.email} (${passwordKey})`);
          results.push({
            mailbox_id: mailbox.id,
            email: mailbox.email,
            error: 'No IMAP password configured',
            folders: []
          });
          continue;
        }

        // IMAP configuration
        const imapConfig = {
          host: mailbox.imap_host,
          port: mailbox.imap_port,
          user: mailbox.imap_username || mailbox.email,
          password: password,
          tls: true,
          tlsOptions: { rejectUnauthorized: false }
        };

        // Connect and list folders
        const folders = await withDenoImapClient(imapConfig, async (client) => {
          return await client.listFolders();
        });

        // Categorize folders
        const categorized = {
          inbox: null as string | null,
          sent: null as string | null,
          drafts: null as string | null,
          trash: null as string | null,
          other: [] as string[]
        };

        for (const folder of folders) {
          // Handle both string and object folder formats
          const folderName = typeof folder === 'string' ? folder : (folder.name || '');
          if (!folderName) continue;
          
          const name = folderName.toLowerCase();
          
          if (name === 'inbox') {
            categorized.inbox = folderName;
          } else if (name.includes('sent')) {
            categorized.sent = folderName;
          } else if (name.includes('draft')) {
            categorized.drafts = folderName;
          } else if (name.includes('trash') || name.includes('deleted')) {
            categorized.trash = folderName;
          } else {
            categorized.other.push(folderName);
          }
        }

        results.push({
          mailbox_id: mailbox.id,
          email: mailbox.email,
          folders: folders,
          categorized: categorized,
          recommended_sync_folders: [
            categorized.inbox,
            categorized.sent
          ].filter(Boolean)
        });

        console.log(`[ListFolders] Found ${folders.length} folders for ${mailbox.email}`);
      } catch (error) {
        console.error(`[ListFolders] Error checking ${mailbox.email}:`, error);
        results.push({
          mailbox_id: mailbox.id,
          email: mailbox.email,
          error: error.message,
          folders: []
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        mailboxes_checked: mailboxes.length,
        results: results
      }, null, 2),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('[ListFolders] Error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

