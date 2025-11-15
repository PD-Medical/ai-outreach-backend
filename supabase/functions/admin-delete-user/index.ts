// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    console.log('Delete user request - Raw body:', JSON.stringify(body))
    console.log('Delete user request - Body keys:', Object.keys(body))

    const { profile_id } = body
    console.log('Extracted profile_id:', profile_id, 'Type:', typeof profile_id)

    // Validate input
    if (!profile_id || typeof profile_id !== 'string' || !profile_id.trim()) {
      console.error('Invalid profile_id:', profile_id)
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'Invalid or missing profile_id',
          received: { profile_id, body_keys: Object.keys(body) }
        }),
        { 
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    const profileId = profile_id.trim()
    console.log('Processing deletion for profile_id:', profileId)

    // Create admin client
    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    // Fetch the profile to get auth_user_id
    // NOTE: Using profile_id as the column name (not id)
    console.log('Fetching profile from database...')
    const { data: profile, error: profileError } = await supabaseAdmin
      .from('profiles')
      .select('profile_id, auth_user_id')
      .eq('profile_id', profileId)
      .maybeSingle()

    if (profileError) {
      console.error('Error fetching profile:', profileError)
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: `Database error: ${profileError.message}`,
          details: profileError
        }),
        { 
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    if (!profile) {
      console.error('Profile not found for profile_id:', profileId)
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: 'Profile not found',
          profile_id: profileId
        }),
        { 
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log('Found profile:', profile)

    // Determine which auth user ID to use
    // If auth_user_id exists, use it; otherwise use the profile_id itself
    const authUserId = profile.auth_user_id || profile.profile_id

    console.log('Attempting to delete auth user:', authUserId)

    // Step 1: Delete from auth.users
    // This should cascade to profile if you have ON DELETE CASCADE set up
    const { error: deleteAuthError } = await supabaseAdmin.auth.admin.deleteUser(
      authUserId
    )

    if (deleteAuthError) {
      console.error('Auth user deletion failed:', deleteAuthError)
      return new Response(
        JSON.stringify({ 
          success: false, 
          error: `Failed to delete auth user: ${deleteAuthError.message}`,
          auth_user_id: authUserId,
          details: deleteAuthError
        }),
        { 
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    console.log('Auth user deleted successfully')

    // Step 2: Delete profile record (if it wasn't cascaded)
    // We'll try to delete it, but ignore errors if it's already gone
    console.log('Attempting to delete profile record...')
    const { error: deleteProfileError } = await supabaseAdmin
      .from('profiles')
      .delete()
      .eq('profile_id', profileId)

    if (deleteProfileError) {
      console.warn('Profile deletion warning (might be already cascaded):', deleteProfileError)
      // Don't fail the request if profile is already deleted by cascade
    } else {
      console.log('Profile deleted successfully')
    }

    console.log('User deletion completed successfully')
    return new Response(
      JSON.stringify({ 
        success: true,
        message: 'User deleted successfully',
        deleted_profile_id: profileId,
        deleted_auth_user_id: authUserId
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )

  } catch (error) {
    console.error('Unexpected error in delete-user function:', error)
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error instanceof Error ? error.message : 'An unexpected error occurred',
        stack: error instanceof Error ? error.stack : undefined
      }),
      { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})