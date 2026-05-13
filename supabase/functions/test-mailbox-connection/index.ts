import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";
import { requireAdmin } from "../_shared/auth.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Allowed IMAP/POP ports for the inline-credentials path. Locks the function
// down to mail-protocol use; combined with the host check below, prevents
// the edge function from being repurposed as an SSRF / internal port-probe
// primitive even by an admin caller.
const ALLOWED_IMAP_PORTS = new Set([993, 143, 995, 110]);

// Hostnames or IP literals that must not be reachable through this function.
// Covers loopback, RFC1918 private ranges, link-local / AWS metadata service,
// and obvious junk. Best-effort string match — DNS-level resolution to
// private space is still possible but requires deliberate misconfiguration
// of public DNS, which is well outside the threat model here.
function isHostBlocked(host: string): boolean {
  const h = host.trim().toLowerCase();
  if (!h) return true;
  if (h === "localhost" || h === "ip6-localhost" || h === "0.0.0.0") return true;
  if (h === "::1" || h.startsWith("fe80:") || h.startsWith("fc") || h.startsWith("fd")) return true;
  if (/^127\./.test(h)) return true;                       // 127.0.0.0/8
  if (/^10\./.test(h)) return true;                        // 10.0.0.0/8
  if (/^192\.168\./.test(h)) return true;                  // 192.168.0.0/16
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(h)) return true;   // 172.16.0.0/12
  if (/^169\.254\./.test(h)) return true;                  // link-local / metadata
  return false;
}

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

  // Auth check — admin only. The inline-credentials branch below would
  // otherwise let any authenticated user open TLS sockets to arbitrary hosts.
  const auth = await requireAdmin(req);
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
      // Disallow internal / metadata / loopback targets.
      if (isHostBlocked(host)) {
        return new Response(
          JSON.stringify({ success: false, error: "host is not allowed" }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
        );
      }
      const portNum = Number.isFinite(port as number) ? Number(port) : 993;
      if (!ALLOWED_IMAP_PORTS.has(portNum)) {
        return new Response(
          JSON.stringify({ success: false, error: `port ${portNum} is not an allowed IMAP/POP port` }),
          { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
        );
      }
      credentials = {
        email: username,
        imap_host: host,
        imap_port: portNum,
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
