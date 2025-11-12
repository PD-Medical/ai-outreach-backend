// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.3"
import { corsHeaders } from "../_shared/cors.ts"

type RoleType = "admin" | "sales" | "accounts" | "management"

type RequestBody = {
  email?: string
  full_name?: string
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

    if (!body.email || !body.full_name) {
      return new Response(JSON.stringify({ success: false, message: "Missing email or full_name" }), {
        status: 400,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      })
    }

    if (body.role && !isRole(body.role)) {
      return new Response(JSON.stringify({ success: false, message: "Invalid role" }), {
        status: 400,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      })
    }

    // Find the auth user by email
    const { data: authUsers, error: listError } = await supabaseAdmin.auth.admin.listUsers()

    if (listError) {
      console.error("Failed to list users", listError)
      return new Response(JSON.stringify({ success: false, message: "Failed to find user" }), {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      })
    }

    const authUser = authUsers.users.find((u) => u.email === body.email)

    if (!authUser) {
      return new Response(
        JSON.stringify({
          success: false,
          message: `No user found with email ${body.email}. The user must sign up first or be created in the auth system.`,
        }),
        {
          status: 404,
          headers: {
            "Content-Type": "application/json",
            ...corsHeaders,
          },
        }
      )
    }

    // Create profile with new schema (auth_user_id)
    let { error: profileError } = await supabaseAdmin.from("profiles").insert({
      auth_user_id: authUser.id,
      full_name: body.full_name,
      role: body.role ?? "sales",
    })

    // If that fails, try old schema (id)
    if (profileError && profileError.message?.includes("column") && profileError.message?.includes("does not exist")) {
      profileError = null
      const oldResult = await supabaseAdmin.from("profiles").insert({
        id: authUser.id,
        full_name: body.full_name,
        role: body.role ?? "sales",
      })
      profileError = oldResult.error
    }

    if (profileError) {
      console.error("Failed to create profile", profileError)
      return new Response(
        JSON.stringify({
          success: false,
          message: `Failed to create profile: ${profileError.message || "Unknown error"}`,
        }),
        {
          status: 500,
          headers: {
            "Content-Type": "application/json",
            ...corsHeaders,
          },
        }
      )
    }

    return new Response(JSON.stringify({ success: true, message: "Profile created successfully" }), {
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    })
  } catch (error) {
    console.error("Unexpected error creating profile", error)
    return new Response(
      JSON.stringify({
        success: false,
        message: error instanceof Error ? error.message : "Unexpected error",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      }
    )
  }
})

