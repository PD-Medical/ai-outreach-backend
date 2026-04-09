/**
 * Email Import Job Edge Function
 *
 * Manages email import jobs with SQS-based batch processing.
 *
 * Endpoints:
 * - POST /start: Create a new import job and invoke Lambda
 * - POST /pause: Pause a running import job
 * - POST /resume: Resume a paused import job
 * - POST /cancel: Cancel an import job
 * - GET /status: Get job status by job_id or mailbox_id
 * - POST /estimate: Estimate email count for a configuration
 *
 * Deploy: supabase functions deploy email-import-job
 */

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuth } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Lambda URL cache (fetched from system_config)
let cachedLambdaUrl: string | null = null;

interface ImportConfig {
  mailbox_id: string;
  import_since?: string;
  days_back?: number;
  months_back?: number;
  max_emails?: number;
  folders?: string[];
  skip_existing?: boolean;
}

interface JobAction {
  job_id: string;
}

/**
 * Get Lambda URL from system_config table (same as email-sync-trigger)
 */
async function getLambdaUrl(supabase: ReturnType<typeof createClient>): Promise<string> {
  if (cachedLambdaUrl) {
    return cachedLambdaUrl;
  }

  const { data, error } = await supabase
    .from("system_config")
    .select("value")
    .eq("key", "email_sync_url")
    .single();

  if (error || !data?.value) {
    throw new Error("email_sync_url not found in system_config");
  }

  cachedLambdaUrl = data.value;
  return cachedLambdaUrl;
}

/**
 * Invoke Lambda function
 */
async function invokeLambda(
  supabase: ReturnType<typeof createClient>,
  mode: string,
  payload: Record<string, unknown>
): Promise<Response> {
  const lambdaUrl = await getLambdaUrl(supabase);

  const response = await fetch(lambdaUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      mode,
      ...payload,
    }),
  });

  return response;
}

/**
 * Handle /start - Create a new import job and invoke Lambda
 */
async function handleStart(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  config: ImportConfig
): Promise<Response> {
  const { mailbox_id, ...importConfig } = config;

  if (!mailbox_id) {
    return new Response(
      JSON.stringify({ success: false, error: "mailbox_id is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Verify mailbox exists and user has access
  const { data: mailbox, error: mailboxError } = await supabase
    .from("mailboxes")
    .select("id, email, name")
    .eq("id", mailbox_id)
    .single();

  if (mailboxError || !mailbox) {
    return new Response(
      JSON.stringify({ success: false, error: "Mailbox not found" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Create job record
  const { data: job, error: jobError } = await supabase
    .from("email_import_jobs")
    .insert({
      mailbox_id,
      config: {
        folders: ["INBOX", "INBOX.Sent"],
        skip_existing: true,
        ...importConfig,
      },
      status: "pending",
      created_by: userId,
    })
    .select()
    .single();

  if (jobError) {
    console.error("Failed to create job:", jobError);
    return new Response(
      JSON.stringify({ success: false, error: "Failed to create import job" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Invoke Lambda with import_init mode (async)
  try {
    const lambdaResponse = await invokeLambda(supabase, "import_init", {
      job_id: job.id,
    });

    if (!lambdaResponse.ok) {
      const errorText = await lambdaResponse.text();
      console.error("Lambda invocation failed:", errorText);

      // Update job status to failed
      await supabase
        .from("email_import_jobs")
        .update({ status: "failed", last_error: `Lambda error: ${errorText}` })
        .eq("id", job.id);

      return new Response(
        JSON.stringify({ success: false, error: "Failed to start import", job_id: job.id }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  } catch (err) {
    console.error("Lambda invocation exception:", err);

    await supabase
      .from("email_import_jobs")
      .update({ status: "failed", last_error: `Invocation error: ${err.message}` })
      .eq("id", job.id);

    return new Response(
      JSON.stringify({ success: false, error: "Failed to invoke Lambda", job_id: job.id }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({
      success: true,
      job_id: job.id,
      status: "initializing",
      mailbox: { id: mailbox.id, email: mailbox.email, name: mailbox.name },
    }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

/**
 * Handle /pause - Pause a running import job
 */
async function handlePause(
  supabase: ReturnType<typeof createClient>,
  action: JobAction
): Promise<Response> {
  const { job_id } = action;

  if (!job_id) {
    return new Response(
      JSON.stringify({ success: false, error: "job_id is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const { data, error } = await supabase
    .from("email_import_jobs")
    .update({ status: "paused" })
    .eq("id", job_id)
    .eq("status", "running")
    .select()
    .single();

  if (error || !data) {
    return new Response(
      JSON.stringify({ success: false, error: "Job not found or not running" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, job_id, status: "paused" }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

/**
 * Handle /resume - Resume a paused import job
 */
async function handleResume(
  supabase: ReturnType<typeof createClient>,
  action: JobAction
): Promise<Response> {
  const { job_id } = action;

  if (!job_id) {
    return new Response(
      JSON.stringify({ success: false, error: "job_id is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Get the job to check status
  const { data: job, error: fetchError } = await supabase
    .from("email_import_jobs")
    .select("*")
    .eq("id", job_id)
    .single();

  if (fetchError || !job) {
    return new Response(
      JSON.stringify({ success: false, error: "Job not found" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  if (job.status !== "paused") {
    return new Response(
      JSON.stringify({ success: false, error: `Job is not paused (status: ${job.status})` }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Update status to running
  await supabase
    .from("email_import_jobs")
    .update({ status: "running" })
    .eq("id", job_id);

  // Re-invoke Lambda to continue
  try {
    await invokeLambda(supabase, "import_init", { job_id });
  } catch (err) {
    console.error("Failed to resume Lambda:", err);
  }

  return new Response(
    JSON.stringify({ success: true, job_id, status: "running" }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

/**
 * Handle /cancel - Cancel an import job
 */
async function handleCancel(
  supabase: ReturnType<typeof createClient>,
  action: JobAction
): Promise<Response> {
  const { job_id } = action;

  if (!job_id) {
    return new Response(
      JSON.stringify({ success: false, error: "job_id is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const { data, error } = await supabase
    .from("email_import_jobs")
    .update({ status: "cancelled" })
    .eq("id", job_id)
    .in("status", ["pending", "running", "paused"])
    .select()
    .single();

  if (error || !data) {
    return new Response(
      JSON.stringify({ success: false, error: "Job not found or already completed" }),
      { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, job_id, status: "cancelled" }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

/**
 * Handle /status - Get job status
 */
async function handleStatus(
  supabase: ReturnType<typeof createClient>,
  url: URL
): Promise<Response> {
  const jobId = url.searchParams.get("job_id");
  const mailboxId = url.searchParams.get("mailbox_id");

  if (!jobId && !mailboxId) {
    return new Response(
      JSON.stringify({ success: false, error: "job_id or mailbox_id is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  let query = supabase
    .from("v_email_import_jobs_summary")
    .select("*")
    .order("created_at", { ascending: false });

  if (jobId) {
    query = query.eq("id", jobId);
  } else if (mailboxId) {
    query = query.eq("mailbox_id", mailboxId);
  }

  const { data: jobs, error } = await query.limit(10);

  if (error) {
    return new Response(
      JSON.stringify({ success: false, error: "Failed to fetch jobs" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ success: true, jobs }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

/**
 * Handle /estimate - Estimate email count for a configuration
 *
 * Accepts two formats:
 * 1. Flat: { mailbox_id, import_since, days_back, months_back, folders }
 * 2. Nested: { mailbox_id, config: { import_since, days_back, months_back, folders } }
 */
async function handleEstimate(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>
): Promise<Response> {
  // Support both flat and nested config formats
  const mailbox_id = body.mailbox_id as string;
  const nestedConfig = body.config as Record<string, unknown> | undefined;
  const importConfig = nestedConfig || body;

  if (!mailbox_id) {
    return new Response(
      JSON.stringify({ success: false, error: "mailbox_id is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    const lambdaResponse = await invokeLambda(supabase, "estimate", {
      mailbox_id,
      config: {
        folders: ["INBOX", "INBOX.Sent"],
        import_since: importConfig.import_since,
        days_back: importConfig.days_back,
        months_back: importConfig.months_back,
      },
    });

    if (!lambdaResponse.ok) {
      const errorText = await lambdaResponse.text();
      return new Response(
        JSON.stringify({ success: false, error: `Estimation failed: ${errorText}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const result = await lambdaResponse.json();
    return new Response(
      JSON.stringify({ success: true, ...result }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ success: false, error: `Estimation error: ${err.message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
}

/**
 * Main handler
 */
serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Auth check
  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;
  const { user: authUser } = auth;

  const url = new URL(req.url);
  const path = url.pathname.split("/").pop() || "";

  // Create Supabase client
  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const userId = authUser?.id || "";

  try {
    // Route based on path
    switch (path) {
      case "start": {
        if (req.method !== "POST") {
          return new Response(
            JSON.stringify({ error: "Method not allowed" }),
            { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const config: ImportConfig = await req.json();
        return handleStart(supabase, userId, config);
      }

      case "pause": {
        if (req.method !== "POST") {
          return new Response(
            JSON.stringify({ error: "Method not allowed" }),
            { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const action: JobAction = await req.json();
        return handlePause(supabase, action);
      }

      case "resume": {
        if (req.method !== "POST") {
          return new Response(
            JSON.stringify({ error: "Method not allowed" }),
            { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const action: JobAction = await req.json();
        return handleResume(supabase, action);
      }

      case "cancel": {
        if (req.method !== "POST") {
          return new Response(
            JSON.stringify({ error: "Method not allowed" }),
            { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const action: JobAction = await req.json();
        return handleCancel(supabase, action);
      }

      case "status": {
        if (req.method !== "GET") {
          return new Response(
            JSON.stringify({ error: "Method not allowed" }),
            { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        return handleStatus(supabase, url);
      }

      case "estimate": {
        if (req.method !== "POST") {
          return new Response(
            JSON.stringify({ error: "Method not allowed" }),
            { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        const body = await req.json();
        return handleEstimate(supabase, body);
      }

      default:
        return new Response(
          JSON.stringify({
            error: "Not found",
            available_endpoints: ["/start", "/pause", "/resume", "/cancel", "/status", "/estimate"],
          }),
          { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
    }
  } catch (error) {
    console.error("Handler error:", error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
