// Supabase Edge Function - Test Database Connection
// Deploy: supabase functions deploy test-db

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  // Only allow GET requests
  if (req.method !== "GET") {
    return new Response(
      JSON.stringify({ success: false, error: "Method not allowed" }),
      {
        status: 405,
        headers: { "Content-Type": "application/json" },
      }
    );
  }

  try {
    // Create Supabase client (automatically uses environment variables)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    );

    // Test database connection with a simple query
    const { data, error } = await supabase
      .from("_test")
      .select("*")
      .limit(1);

    // Note: Table might not exist, that's okay - we're just testing connection
    const isConnected = !error || error.code === "PGRST204" || error.code === "42P01";

    if (!isConnected) {
      throw error;
    }

    return new Response(
      JSON.stringify({
        success: true,
        data: {
          connected: true,
          timestamp: new Date().toISOString(),
          message: "Database connection successful",
        },
      }),
      {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  } catch (error: any) {
    return new Response(
      JSON.stringify({
        success: false,
        error: `Database connection failed: ${error.message}`,
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    );
  }
});


