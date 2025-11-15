// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { Resend } from "https://esm.sh/resend@latest"
import { corsHeaders } from "../_shared/cors.ts"

type RoleType = "admin" | "sales" | "accounts" | "management"

type RequestBody = {
  email?: string
  full_name?: string
  role?: RoleType
  password?: string
  send_password?: boolean
}

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
const resendApiKey = Deno.env.get("RESEND_API_KEY") ?? ""
const resendFromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? ""

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing required Supabase environment variables")
}

if (!resendApiKey) {
  throw new Error("Missing RESEND_API_KEY environment variable")
}

if (!resendFromEmail) {
  throw new Error("Missing RESEND_FROM_EMAIL environment variable")
}

const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
})

const resend = new Resend(resendApiKey)

const DEFAULT_ROLE: RoleType = "sales"

function isRole(value: unknown): value is RoleType {
  return value === "admin" || value === "sales" || value === "accounts" || value === "management"
}

function generatePassword(length = 12): string {
  const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
  const values = crypto.getRandomValues(new Uint32Array(length))
  return Array.from(values, (x) => charset[x % charset.length]).join("")
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders })
  }

  if (request.method !== "POST") {
    return new Response(JSON.stringify({ success: false, message: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    })
  }

  try {
    const body = (await request.json()) as RequestBody

    if (!body.email?.trim() || !body.full_name?.trim()) {
      return new Response(JSON.stringify({ success: false, message: "Missing email or full_name" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      })
    }

    if (body.role && !isRole(body.role)) {
      return new Response(JSON.stringify({ success: false, message: "Invalid role" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      })
    }

    const password = body.password || generatePassword(14)

    const { data: createResult, error: createError } = await supabaseAdmin.auth.admin.createUser({
      email: body.email.trim().toLowerCase(),
      email_confirm: true,
      password,
      user_metadata: {
        full_name: body.full_name.trim(),
        role: body.role ?? DEFAULT_ROLE,
      },
    })

    if (createError || !createResult?.user) {
      console.error("Failed to create auth user", createError)
      return new Response(
        JSON.stringify({
          success: false,
          message: createError?.message || "Failed to create auth user",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        }
      )
    }

    const authUserId = createResult.user.id

    let { error: profileError } = await supabaseAdmin.from("profiles").insert({
      auth_user_id: authUserId,
      full_name: body.full_name.trim(),
      role: body.role ?? DEFAULT_ROLE,
    })

    if (profileError && profileError.message?.includes("column") && profileError.message?.includes("auth_user_id")) {
      const legacyResult = await supabaseAdmin.from("profiles").insert({
        id: authUserId,
        full_name: body.full_name.trim(),
        role: body.role ?? DEFAULT_ROLE,
      })
      profileError = legacyResult.error
    }

    if (profileError) {
      console.error("Failed to create profile", profileError)

      // Clean up auth user if profile creation fails
      await supabaseAdmin.auth.admin.deleteUser(authUserId)

      return new Response(
        JSON.stringify({
          success: false,
          message: `Failed to create profile: ${profileError.message || "Unknown error"}`,
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        }
      )
    }

    await resend.emails.send({
      from: resendFromEmail,
      to: body.email.trim().toLowerCase(),
      subject: "Your new account",
      html: `
        <p>Hi ${body.full_name.trim()},</p>
        <p>Your account is ready.</p>
        <p>Email: ${body.email.trim().toLowerCase()}</p>
        <p>Password: ${password}</p>
        <p>Please change it after logging in.</p>
      `,
    })

    return new Response(
      JSON.stringify({
        success: true,
        message: "User created successfully",
        user_id: authUserId,
        email: body.email.trim().toLowerCase(),
      }),
      { status: 200, headers: { "Content-Type": "application/json", ...corsHeaders } }
    )
  } catch (error) {
    console.error("Unexpected error creating user", error)
    return new Response(
      JSON.stringify({
        success: false,
        message: error instanceof Error ? error.message : "Unexpected error",
      }),
      { status: 500, headers: { "Content-Type": "application/json", ...corsHeaders } }
    )
  }
})


