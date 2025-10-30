/**
 * Database Tools
 * Supabase database operations for agents
 */

import { tool } from "langchain"
import { z } from "zod"
import { createClient } from "supabase"

// Create Supabase client
const getSupabaseClient = () => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  return createClient(supabaseUrl, supabaseKey)
}

/**
 * Query contacts from database
 */
export const queryContactsTool = tool(
  async (input: { limit?: number; filters?: Record<string, any> }) => {
    const supabase = getSupabaseClient()
    
    let query = supabase
      .from("contacts")
      .select("*")
      .limit(input.limit || 10)
    
    // Apply filters if provided
    if (input.filters) {
      Object.entries(input.filters).forEach(([key, value]) => {
        query = query.eq(key, value)
      })
    }
    
    const { data, error } = await query
    
    if (error) {
      throw new Error(`Database error: ${error.message}`)
    }
    
    return JSON.stringify(data)
  },
  {
    name: "query_contacts",
    description: "Query contacts from the database. Use this to retrieve contact information.",
    schema: z.object({
      limit: z.number().optional().describe("Maximum number of contacts to return (default: 10)"),
      filters: z.record(z.any()).optional().describe("Filters to apply to the query"),
    }),
  }
)

/**
 * Update contact in database
 */
export const updateContactTool = tool(
  async (input: { contactId: string; updates: Record<string, any> }) => {
    const supabase = getSupabaseClient()
    
    const { data, error } = await supabase
      .from("contacts")
      .update(input.updates)
      .eq("id", input.contactId)
      .select()
    
    if (error) {
      throw new Error(`Database error: ${error.message}`)
    }
    
    return JSON.stringify({ success: true, contact: data })
  },
  {
    name: "update_contact",
    description: "Update a contact in the database. Use this to modify contact information.",
    schema: z.object({
      contactId: z.string().describe("The ID of the contact to update"),
      updates: z.record(z.any()).describe("The fields to update"),
    }),
  }
)

