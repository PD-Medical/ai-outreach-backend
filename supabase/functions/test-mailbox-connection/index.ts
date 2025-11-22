import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RequestBody {
  mailbox_id: string;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Create admin client
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body: RequestBody = await req.json();
    const { mailbox_id } = body;

    if (!mailbox_id) {
      return new Response(
        JSON.stringify({ success: false, error: "mailbox_id is required" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
      );
    }

    // Get mailbox credentials using RPC function
    const { data: credentials, error: credError } = await supabase.rpc(
      "get_mailbox_credentials",
      { p_mailbox_id: mailbox_id }
    );

    if (credError) {
      console.error("Failed to get credentials:", credError);
      return new Response(
        JSON.stringify({ success: false, error: "Failed to retrieve mailbox credentials" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }

    if (!credentials?.success) {
      return new Response(
        JSON.stringify({ success: false, error: credentials?.error || "Mailbox not found" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 404 }
      );
    }

    // Check if password is available
    if (!credentials.password) {
      // Try fallback to environment variable (backward compatibility)
      const envPassword = Deno.env.get(`IMAP_PASSWORD_${mailbox_id.replace(/-/g, "_")}`);
      if (!envPassword) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "No password configured for this mailbox. Please update the mailbox settings."
          }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
        );
      }
      credentials.password = envPassword;
    }

    // Import IMAP client
    const { ImapClient } = await import("../_shared/email/deno-imap-client.ts");

    // Create IMAP connection
    const imapConfig = {
      host: credentials.imap_host,
      port: credentials.imap_port,
      user: credentials.imap_username,
      password: credentials.password,
      tls: true,
      tlsOptions: { rejectUnauthorized: false },
    };

    console.log(`Testing connection to ${credentials.email} via ${imapConfig.host}:${imapConfig.port}`);

    const client = new ImapClient(imapConfig);

    try {
      await client.connect();

      // List folders to verify connection
      const folders = await client.listFolders();

      await client.disconnect();

      console.log(`Connection test successful. Found ${folders.length} folders.`);

      return new Response(
        JSON.stringify({
          success: true,
          email: credentials.email,
          folders: folders.map((f: { name: string }) => f.name),
          message: `Successfully connected to ${credentials.email}`,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    } catch (imapError) {
      console.error("IMAP connection error:", imapError);
      await client.disconnect().catch(() => {});

      return new Response(
        JSON.stringify({
          success: false,
          error: imapError instanceof Error ? imapError.message : "IMAP connection failed",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }
  } catch (error) {
    console.error("Test connection error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error instanceof Error ? error.message : "Unknown error occurred",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
