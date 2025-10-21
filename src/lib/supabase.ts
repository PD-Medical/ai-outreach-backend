import { createClient, SupabaseClient } from '@supabase/supabase-js';

// Supabase client configuration
let supabase: SupabaseClient | null = null;

/**
 * Get Supabase client instance (singleton pattern)
 * @returns Supabase client
 */
export function getSupabaseClient(): SupabaseClient {
  if (!supabase) {
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_ANON_KEY;

    if (!supabaseUrl || !supabaseKey) {
      throw new Error('Missing Supabase environment variables');
    }

    supabase = createClient(supabaseUrl, supabaseKey);
  }

  return supabase;
}

/**
 * Get Supabase admin client (with service role key)
 * Use this for admin operations that bypass RLS
 * @returns Supabase admin client
 */
export function getSupabaseAdmin(): SupabaseClient {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseServiceKey) {
    throw new Error('Missing Supabase admin environment variables');
  }

  return createClient(supabaseUrl, supabaseServiceKey);
}

