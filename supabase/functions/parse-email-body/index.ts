/**
 * Parse Email Body Edge Function
 * 
 * Parses large email bodies on-demand when viewed in the UI.
 * Large emails (>100KB) are stored with raw body during sync to avoid CPU timeout.
 * This function fetches the raw body, parses it properly, and updates the database.
 * 
 * Deploy: supabase functions deploy parse-email-body
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { corsHeaders } from '../_shared/cors.ts';
import { extractPlainText } from '../_shared/email/imap-client.ts';

interface RequestBody {
  email_id: string;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    console.log('[ParseBody] Starting email body parsing');

    // Parse request body
    const body: RequestBody = await req.json();
    const { email_id } = body;

    if (!email_id) {
      return new Response(
        JSON.stringify({ error: 'email_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // Fetch email from database
    const { data: email, error: fetchError } = await supabase
      .from('emails')
      .select('id, body_plain, needs_parsing')
      .eq('id', email_id)
      .single();

    if (fetchError) {
      throw new Error(`Failed to fetch email: ${fetchError.message}`);
    }

    if (!email) {
      return new Response(
        JSON.stringify({ error: 'Email not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Check if email needs parsing
    if (!email.needs_parsing) {
      console.log('[ParseBody] Email does not need parsing');
      return new Response(
        JSON.stringify({
          success: true,
          message: 'Email already parsed',
          body_plain: email.body_plain
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Parse the raw body
    console.log(`[ParseBody] Parsing email body (${email.body_plain?.length || 0} bytes)`);
    const parsedBody = extractPlainText(email.body_plain || '');
    console.log(`[ParseBody] Parsed body length: ${parsedBody.length} bytes`);

    // Update database with parsed body
    const { error: updateError } = await supabase
      .from('emails')
      .update({
        body_plain: parsedBody,
        needs_parsing: false,
        updated_at: new Date().toISOString()
      })
      .eq('id', email_id);

    if (updateError) {
      throw new Error(`Failed to update email: ${updateError.message}`);
    }

    console.log('[ParseBody] Successfully parsed and updated email');

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Email body parsed successfully',
        body_plain: parsedBody,
        original_size: email.body_plain?.length || 0,
        parsed_size: parsedBody.length
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('[ParseBody] Error:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

