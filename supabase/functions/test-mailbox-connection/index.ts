import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";
import { requireAuth } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface RequestBody {
  // Existing mailbox: look up stored credentials.
  mailbox_id?: string;
  // New / unsaved mailbox: test the supplied credentials directly.
  host?: string;
  port?: number;
  username?: string;
  password?: string;
}

interface ImapCredentials {
  email: string;
  imap_host: string;
  imap_port: number;
  imap_username: string;
  password: string;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  // Auth check
  const auth = await requireAuth(req);
  if (auth instanceof Response) return auth;

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Create admin client
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const body: RequestBody = await req.json();
    const { mailbox_id } = body;

    let credentials: ImapCredentials;

    if (mailbox_id) {
      // Existing mailbox: pull stored credentials via RPC.
      const { data: creds, error: credError } = await supabase.rpc(
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

      if (!creds?.success) {
        return new Response(
          JSON.stringify({ success: false, error: creds?.error || "Mailbox not found" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 404 }
        );
      }

      let password: string | undefined = creds.password;
      if (!password) {
        // Fallback to environment variable (backward compatibility).
        password = Deno.env.get(`IMAP_PASSWORD_${mailbox_id.replace(/-/g, "_")}`) ?? undefined;
        if (!password) {
          return new Response(
            JSON.stringify({
              success: false,
              error: "No password configured for this mailbox. Please update the mailbox settings."
            }),
            { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
          );
        }
      }

      credentials = {
        email: creds.email,
        imap_host: creds.imap_host,
        imap_port: creds.imap_port,
        imap_username: creds.imap_username,
        password,
      };
    } else {
      // New / unsaved mailbox: test the supplied credentials directly.
      const { host, port, username, password } = body;
      if (!host || !username || !password) {
        return new Response(
          JSON.stringify({ success: false, error: "host, username and password are required" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
        );
      }
      credentials = {
        email: username,
        imap_host: host,
        imap_port: port || 993,
        imap_username: username,
        password,
      };
    }

    // Import IMAP client
    const { DenoImapClient } = await import("../_shared/email/deno-imap-client.ts");

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

    const client = new DenoImapClient(imapConfig);

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
