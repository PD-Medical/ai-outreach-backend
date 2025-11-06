/**
 * Toggle Cron Job Edge Function
 * 
 * Enable or disable the automatic email sync cron job
 * Can be called from UI to toggle sync on/off
 * 
 * Deploy: supabase functions deploy toggle-cron-job
 * 
 * Usage:
 * POST /functions/v1/toggle-cron-job
 * Body: { "enabled": true } or { "enabled": false }
 */

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const CRON_JOB_NAME = 'sync-emails-every-minute';
const CRON_SCHEDULE = '* * * * *'; // Every minute

/**
 * Check if cron job exists
 */
async function isCronJobEnabled(supabase: any): Promise<boolean> {
  const { data, error } = await supabase
    .rpc('check_cron_job_exists', { job_name: CRON_JOB_NAME });

  if (error) {
    // Fallback: query cron.job directly
    const query = `SELECT COUNT(*) as count FROM cron.job WHERE jobname = '${CRON_JOB_NAME}'`;
    const { data: result } = await supabase.rpc('exec_sql', { sql: query });
    return result?.[0]?.count > 0;
  }

  return data;
}

/**
 * Enable the cron job
 */
async function enableCronJob(supabase: any): Promise<{ success: boolean; message: string }> {
  // Check if already enabled
  const exists = await isCronJobEnabled(supabase);
  if (exists) {
    return { success: true, message: 'Cron job is already enabled' };
  }

  // Get database settings
  const { data: settings, error: settingsError } = await supabase.rpc('get_db_settings');
  
  if (settingsError) {
    throw new Error('Failed to get database settings. Make sure app.settings.* are configured.');
  }

  // Schedule the cron job using SQL
  const scheduleSql = `
    SELECT cron.schedule(
      '${CRON_JOB_NAME}',
      '${CRON_SCHEDULE}',
      $$
      SELECT net.http_post(
        url := current_setting('app.settings.supabase_url', true) || '/functions/v1/sync-emails',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := jsonb_build_object(
          'triggered_at', now(),
          'source', 'pg_cron',
          'job_name', '${CRON_JOB_NAME}'
        ),
        timeout_milliseconds := 55000
      ) AS request_id;
      $$
    );
  `;

  const { error } = await supabase.rpc('exec_sql', { sql: scheduleSql });

  if (error) {
    throw new Error(`Failed to schedule cron job: ${error.message}`);
  }

  return { success: true, message: 'Cron job enabled successfully' };
}

/**
 * Disable the cron job
 */
async function disableCronJob(supabase: any): Promise<{ success: boolean; message: string }> {
  // Check if job exists
  const exists = await isCronJobEnabled(supabase);
  if (!exists) {
    return { success: true, message: 'Cron job is already disabled' };
  }

  // Unschedule the cron job
  const unscheduleSql = `SELECT cron.unschedule('${CRON_JOB_NAME}');`;
  const { error } = await supabase.rpc('exec_sql', { sql: unscheduleSql });

  if (error) {
    throw new Error(`Failed to unschedule cron job: ${error.message}`);
  }

  return { success: true, message: 'Cron job disabled successfully' };
}

/**
 * Get cron job status
 */
async function getCronJobStatus(supabase: any): Promise<{
  enabled: boolean;
  jobName: string;
  schedule?: string;
  lastRun?: string;
}> {
  const enabled = await isCronJobEnabled(supabase);

  if (!enabled) {
    return {
      enabled: false,
      jobName: CRON_JOB_NAME
    };
  }

  // Get job details
  const { data: job } = await supabase
    .from('cron.job')
    .select('schedule, jobname')
    .eq('jobname', CRON_JOB_NAME)
    .single();

  // Get last run
  const { data: lastRun } = await supabase
    .from('cron.job_run_details')
    .select('start_time, status')
    .eq('jobname', CRON_JOB_NAME)
    .order('start_time', { ascending: false })
    .limit(1)
    .single();

  return {
    enabled: true,
    jobName: CRON_JOB_NAME,
    schedule: job?.schedule,
    lastRun: lastRun?.start_time
  };
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
        'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  try {
    // Create Supabase client with service role key
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // GET request - return status
    if (req.method === 'GET') {
      const status = await getCronJobStatus(supabase);

      return new Response(JSON.stringify(status), {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    // POST request - toggle cron job
    if (req.method === 'POST') {
      const body = await req.json();
      const { enabled } = body;

      if (typeof enabled !== 'boolean') {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Invalid request. Body must contain "enabled" boolean field.'
          }),
          {
            status: 400,
            headers: { 'Content-Type': 'application/json' },
          }
        );
      }

      let result;
      if (enabled) {
        result = await enableCronJob(supabase);
      } else {
        result = await disableCronJob(supabase);
      }

      // Get updated status
      const status = await getCronJobStatus(supabase);

      return new Response(
        JSON.stringify({
          ...result,
          status
        }),
        {
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
          },
        }
      );
    }

    // Method not allowed
    return new Response(
      JSON.stringify({ success: false, error: 'Method not allowed' }),
      {
        status: 405,
        headers: { 'Content-Type': 'application/json' },
      }
    );
  } catch (error) {
    console.error('[Toggle Cron] Error:', error);

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message
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


