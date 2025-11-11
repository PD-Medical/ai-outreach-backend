// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.3"
import { corsHeaders } from "../_shared/cors.ts"

type RoleType = "admin" | "sales" | "accounts" | "management"

type RequestBody = {
  userId?: string
  role?: RoleType
}

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing required Supabase environment variables")
}

const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
})

function isRole(value: unknown): value is RoleType {
  return value === "admin" || value === "sales" || value === "accounts" || value === "management"
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders })
  }

  if (request.method !== "POST") {
    return new Response(JSON.stringify({ success: false, message: "Method not allowed" }), {
      status: 405,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    })
  }

  try {
    const body = (await request.json()) as RequestBody

    if (!body.userId || !body.role) {
      return new Response(JSON.stringify({ success: false, message: "Missing userId or role" }), {
        status: 400,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      })
    }

    if (!isRole(body.role)) {
      return new Response(JSON.stringify({ success: false, message: "Invalid role" }), {
        status: 400,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      })
    }

    const updateProfile = await supabaseAdmin
      .from("profiles")
      .update({ role: body.role })
      .eq("id", body.userId)

    if (updateProfile.error) {
      console.error("Failed to update profile role", updateProfile.error)
      return new Response(JSON.stringify({ success: false, message: "Failed to update profile role" }), {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      })
    }

    const updateMetadata = await supabaseAdmin.auth.admin.updateUserById(body.userId, {
      app_metadata: { role: body.role },
    })

    if (updateMetadata.error) {
      console.error("Failed to update user metadata", updateMetadata.error)
      return new Response(JSON.stringify({ success: false, message: "Failed to update auth metadata" }), {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      })
    }

    return new Response(JSON.stringify({ success: true, message: "Role updated" }), {
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    })
  } catch (error) {
    console.error("Unexpected error updating role", error)
    return new Response(JSON.stringify({ success: false, message: "Unexpected error" }), {
      status: 500,
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    })
  }
})

