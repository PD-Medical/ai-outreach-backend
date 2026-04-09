import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { corsHeaders } from '../_shared/cors.ts';
import { requireAdmin } from '../_shared/auth.ts';

const CRON_JOB_NAME = 'mailchimp-newsletter-sync';
const DEFAULT_SCHEDULE_RATE = '30 minutes';
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

interface SchedulerRequest {
  enabled?: boolean;
  schedule_rate?: string;
}

function isServiceRoleRequest(req: Request): boolean {
  const authHeader = req.headers.get('authorization') ?? '';
  if (!authHeader.startsWith('Bearer ')) return false;
  return authHeader.replace('Bearer ', '') === SERVICE_ROLE_KEY;
}

function scheduleRateToCron(rate: string): string {
  switch (rate) {
    case '5 minutes':
      return '*/5 * * * *';
    case '10 minutes':
      return '*/10 * * * *';
    case '15 minutes':
      return '*/15 * * * *';
    case '30 minutes':
      return '*/30 * * * *';
    case '1 hour':
      return '0 * * * *';
    default:
      throw new Error(`Unsupported schedule rate: ${rate}`);
  }
}

async function isCronJobEnabled(supabase: any): Promise<boolean> {
  const { data, error } = await supabase.rpc('check_cron_job_exists', { job_name: CRON_JOB_NAME });
  if (error) {
    throw new Error(`Failed to check cron job: ${error.message}`);
  }
  return Boolean(data);
}

async function upsertSchedulerConfig(
  supabase: any,
  enabled: boolean,
  scheduleRate: string,
) {
  const { error } = await supabase
    .from('system_config')
    .upsert([
      {
        key: 'mailchimp_newsletter_sync_enabled',
        value: enabled,
        description: 'Toggle scheduled sync of external Mailchimp newsletters.',
      },
      {
        key: 'mailchimp_newsletter_sync_schedule_rate',
        value: scheduleRate,
        description: 'Schedule rate for syncing external Mailchimp newsletters.',
      },
    ], { onConflict: 'key' });

  if (error) {
    throw new Error(`Failed to update Mailchimp scheduler config: ${error.message}`);
  }
}

async function enableCronJob(
  supabase: any,
  scheduleRate: string,
): Promise<void> {
  const cronExpression = scheduleRateToCron(scheduleRate);
  const exists = await isCronJobEnabled(supabase);

  if (exists) {
    const { error } = await supabase.rpc('exec_sql', {
      sql: `SELECT cron.unschedule('${CRON_JOB_NAME}');`,
    });
    if (error) {
      throw new Error(`Failed to reset Mailchimp cron job: ${error.message}`);
    }
  }

  const scheduleSql = `
    SELECT cron.schedule(
      '${CRON_JOB_NAME}',
      '${cronExpression}',
      $$
      SELECT net.http_post(
        url := current_setting('app.settings.supabase_url', true) || '/functions/v1/sync-mailchimp-newsletters',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
        ),
        body := jsonb_build_object(
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
    throw new Error(`Failed to schedule Mailchimp sync job: ${error.message}`);
  }
}

async function disableCronJob(supabase: any): Promise<void> {
  const exists = await isCronJobEnabled(supabase);
  if (!exists) return;

  const { error } = await supabase.rpc('exec_sql', {
    sql: `SELECT cron.unschedule('${CRON_JOB_NAME}');`,
  });
  if (error) {
    throw new Error(`Failed to disable Mailchimp sync job: ${error.message}`);
  }
}

async function getSchedulerStatus(supabase: any) {
  const { data: configRows, error: configError } = await supabase
    .from('system_config')
    .select('key, value')
    .in('key', [
      'mailchimp_newsletter_sync_enabled',
      'mailchimp_newsletter_sync_schedule_rate',
    ]);

  if (configError) {
    throw new Error(`Failed to load Mailchimp scheduler config: ${configError.message}`);
  }

  const configEntries = (configRows ?? []) as Array<{ key: string; value: unknown }>;
  const configMap = new Map(configEntries.map((row) => [row.key, row.value]));
  const enabled = await isCronJobEnabled(supabase);
  const configuredEnabled = Boolean(configMap.get('mailchimp_newsletter_sync_enabled') ?? false);
  const scheduleRate = String(configMap.get('mailchimp_newsletter_sync_schedule_rate') ?? DEFAULT_SCHEDULE_RATE);

  const { data: jobData } = await supabase
    .from('cron.job')
    .select('schedule, jobname')
    .eq('jobname', CRON_JOB_NAME)
    .maybeSingle();
  const job = jobData as { schedule?: string | null; jobname?: string | null } | null;

  const { data: lastRunData } = await supabase
    .from('cron.job_run_details')
    .select('start_time, end_time, status, return_message')
    .eq('jobname', CRON_JOB_NAME)
    .order('start_time', { ascending: false })
    .limit(1)
    .maybeSingle();
  const lastRun = lastRunData as {
    start_time?: string | null;
    end_time?: string | null;
    status?: string | null;
    return_message?: string | null;
  } | null;

  return {
    enabled,
    configured_enabled: configuredEnabled,
    schedule_rate: scheduleRate,
    cron_schedule: job?.schedule ?? null,
    job_name: CRON_JOB_NAME,
    last_run: lastRun ?? null,
  };
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  if (!isServiceRoleRequest(req)) {
    const auth = await requireAdmin(req);
    if (auth instanceof Response) return auth;
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  );

  try {
    if (req.method === 'GET') {
      const status = await getSchedulerStatus(supabase);
      return new Response(JSON.stringify(status), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const body: SchedulerRequest = await req.json();
    const enabled = Boolean(body.enabled);
    const scheduleRate = body.schedule_rate ?? DEFAULT_SCHEDULE_RATE;

    await upsertSchedulerConfig(supabase, enabled, scheduleRate);

    if (enabled) {
      await enableCronJob(supabase, scheduleRate);
    } else {
      await disableCronJob(supabase);
    }

    const status = await getSchedulerStatus(supabase);
    return new Response(JSON.stringify({ ok: true, status }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error('[MailchimpNewsletterSyncScheduler] Error:', error);
    const message = error instanceof Error ? error.message : 'Unknown scheduler error';
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
