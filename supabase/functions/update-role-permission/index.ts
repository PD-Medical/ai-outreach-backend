// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.3"
import { corsHeaders } from "../_shared/cors.ts"

type RoleType = "admin" | "sales" | "accounts" | "management"

type RequestBody = {
  role?: RoleType
  column?: string
  value?: boolean
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

// Valid column names in role_permissions table
const validColumns = [
  "view_users",
  "manage_users",
  "view_contacts",
  "manage_contacts",
  "view_workflows",
  "view_campaigns",
  "view_emails",
  "manage_campaigns",
  "approve_campaigns",
  "view_analytics",
  "manage_approvals",
  "view_products",  
  "manage_products",
]

function isValidColumn(column: string): boolean {
  return validColumns.includes(column)
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

    if (!body.role || !body.column || typeof body.value === "undefined") {
      return new Response(
        JSON.stringify({ success: false, message: "Missing role, column, or value" }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
            ...corsHeaders,
          },
        }
      )
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

    if (!isValidColumn(body.column)) {
      return new Response(JSON.stringify({ success: false, message: "Invalid column name" }), {
        status: 400,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      })
    }

    // Update the role_permissions table
    const { error } = await supabaseAdmin
      .from("role_permissions")
      .update({ [body.column]: body.value })
      .eq("role", body.role)

    if (error) {
      console.error("Failed to update role permission", error)
      return new Response(
        JSON.stringify({ success: false, message: error.message || "Failed to update permission" }),
        {
          status: 500,
          headers: {
            "Content-Type": "application/json",
            ...corsHeaders,
          },
        }
      )
    }

    return new Response(JSON.stringify({ success: true, message: "Permission updated" }), {
      headers: {
        "Content-Type": "application/json",
        ...corsHeaders,
      },
    })
  } catch (error) {
    console.error("Unexpected error updating permission", error)
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

