// Supabase Edge Function - Import Contacts Supervisor
// Generic function to import contacts from multiple sources
// Deploy: supabase functions deploy import-contacts-supervisor

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { importFromEmailServer as emailServerImport } from './email-server.ts';
import { importFromMailchimp as mailchimpImport } from './mailchimp.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface ImportRequest {
  source: 'email_server' | 'mailchimp';
  email_id?: string; // For email_server: which email account to import from
  mailchimp_list_id?: string; // For mailchimp: which list to import
  limit?: number; // Optional limit for number of contacts
}

interface ImportResult {
  success: boolean;
  source: string;
  extracted: number;
  inserted: number;
  errors: number;
  message: string;
  details?: any;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // Parse request body with better error handling
    let request: ImportRequest;
    try {
      const body = await req.json();
      console.log(`[REQUEST] Raw request body:`, JSON.stringify(body, null, 2));
      request = body;
    } catch (error) {
      console.log(`[WARN] JSON parsing failed, using defaults:`, error.message);
      request = {
        source: 'email_server',
        email_id: Deno.env.get("EMAIL_USER") || "peter@pdmedical.com.au"
      };
    }

    console.log(`[START] Starting import from ${request.source}...`);
    console.log(`[REQUEST] Request details:`, JSON.stringify(request, null, 2));

    let result: ImportResult;

    // Route to appropriate import function
    switch (request.source) {
      case 'email_server':
        result = await importFromEmailServer(supabaseClient, request);
        break;
      case 'mailchimp':
        result = await importFromMailchimp(supabaseClient, request);
        break;
      default:
        throw new Error(`Unsupported source: ${request.source}`);
    }

    return new Response(
      JSON.stringify({
        success: result.success,
        source: result.source,
        extracted: result.extracted,
        inserted: result.inserted,
        errors: result.errors,
        message: result.message,
        details: result.details,
        timestamp: new Date().toISOString()
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: result.success ? 200 : 500,
      }
    );

  } catch (error) {
    console.error("[ERROR] Supervisor error:", error);
    
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || "Failed to import contacts",
        details: error.toString(),
        timestamp: new Date().toISOString()
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    );
  }
});

// Email Server Import Function
async function importFromEmailServer(supabaseClient: any, request: ImportRequest): Promise<ImportResult> {
  try {
    const limit = request.limit || 500;
    
    // Process one email account at a time for maximum extraction
    const emailAccount = request.email_id || 'peter@pdmedical.com.au';
    
    console.log(`[EMAIL] Importing from single account: ${emailAccount}`);
    
    // Import contacts from single email account
    const { contacts, message } = await emailServerImport([emailAccount], limit);
    
    // Insert contacts into database with batch processing
    let insertedCount = 0;
    let errorCount = 0;
    
    if (contacts.length > 0) {
      const batchSize = 500;
      
      for (let i = 0; i < contacts.length; i += batchSize) {
        const batch = contacts.slice(i, i + batchSize);
        
        try {
          const { error } = await supabaseClient
            .from('contacts')
            .upsert(batch, { 
              onConflict: 'email',
              ignoreDuplicates: false 
            });

          if (error) {
            console.error(`[ERROR] Email server batch failed:`, error.message);
            errorCount += batch.length;
          } else {
            insertedCount += batch.length;
          }
        } catch (batchError) {
          console.error(`[ERROR] Email server batch exception:`, batchError);
          errorCount += batch.length;
        }
      }
      
      console.log(`[SUCCESS] Email server: ${insertedCount}/${contacts.length} contacts inserted`);
    }
    
    return {
      success: true,
      source: 'email_server',
      extracted: contacts.length,
      inserted: insertedCount,
      errors: errorCount,
      message: message,
      details: { email_account: emailAccount, limit }
    };
    
  } catch (error) {
    console.error("[ERROR] Email server import failed:", error);
    return {
      success: false,
      source: 'email_server',
      extracted: 0,
      inserted: 0,
      errors: 1,
      message: `Email server import failed: ${error.message}`,
      details: { error: error.message }
    };
  }
}

// Mailchimp Import Function
async function importFromMailchimp(supabaseClient: any, request: ImportRequest): Promise<ImportResult> {
  try {
    console.log(`[MAILCHIMP] Mailchimp function called with request:`, JSON.stringify(request, null, 2));
    
    const listId = request.mailchimp_list_id;
    if (!listId) {
      throw new Error("mailchimp_list_id is required for Mailchimp import");
    }
    
    const limit = request.limit || 10000; // Increased default limit
    
    console.log(`[MAILCHIMP] Importing from Mailchimp list: ${listId}`);
    
    // Import contacts from Mailchimp
    const { contacts, message } = await mailchimpImport(supabaseClient, listId, limit);
    
    // Insert contacts into database with batch processing
    let insertedCount = 0;
    let errorCount = 0;
    
    if (contacts.length > 0) {
      const batchSize = 500;
      
      for (let i = 0; i < contacts.length; i += batchSize) {
        const batch = contacts.slice(i, i + batchSize);
        
        try {
          const { error } = await supabaseClient
            .from('contacts')
            .upsert(batch, { 
              onConflict: 'email',
              ignoreDuplicates: false 
            });

          if (error) {
            console.error(`[ERROR] Mailchimp batch failed:`, error.message);
            errorCount += batch.length;
          } else {
            insertedCount += batch.length;
          }
        } catch (batchError) {
          console.error(`[ERROR] Mailchimp batch exception:`, batchError);
          errorCount += batch.length;
        }
      }
      
      console.log(`[SUCCESS] Mailchimp: ${insertedCount}/${contacts.length} contacts inserted`);
    }
    
    return {
      success: true,
      source: 'mailchimp',
      extracted: contacts.length,
      inserted: insertedCount,
      errors: errorCount,
      message: message,
      details: { list_id: listId, limit }
    };
    
  } catch (error) {
    console.error("[ERROR] Mailchimp import failed:", error);
    return {
      success: false,
      source: 'mailchimp',
      extracted: 0,
      inserted: 0,
      errors: 1,
      message: `Mailchimp import failed: ${error.message}`,
      details: { error: error.message }
    };
  }
}
