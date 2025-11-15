// @ts-nocheck
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { Resend } from "https://esm.sh/resend@latest"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const resendApiKey = Deno.env.get('RESEND_API_KEY') ?? ''
const resendFromEmail = Deno.env.get('RESEND_FROM_EMAIL') ?? ''

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error('Missing required Supabase environment variables')
}

if (!resendApiKey) {
  throw new Error('Missing RESEND_API_KEY environment variable')
}

if (!resendFromEmail) {
  throw new Error('Missing RESEND_FROM_EMAIL environment variable')
}

const supabaseAdmin = createClient(
  supabaseUrl,
  serviceRoleKey,
  {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  }
)

const resend = new Resend(resendApiKey)

// Generate secure password
function generatePassword(length = 12): string {
  const charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*'
  const values = crypto.getRandomValues(new Uint32Array(length))
  return Array.from(values, (x) => charset[x % charset.length]).join('')
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { profile_id, email } = await req.json()

    if (!profile_id || !email) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required fields: profile_id, email' }),
        { 
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Create admin client
    // Get auth_user_id from profile (or use id if auth_user_id doesn't exist)
    let profile: any
    let profileError: any
    
    try {
      const result = await supabaseAdmin
        .from('profiles')
        .select('auth_user_id, id, full_name')
        .eq('id', profile_id)
        .single()
      profile = result.data
      profileError = result.error
    } catch (err: any) {
      // If auth_user_id column doesn't exist, use id
      if (err?.message?.includes('auth_user_id') || err?.code === '42703') {
        const result = await supabaseAdmin
          .from('profiles')
          .select('id, full_name')
          .eq('id', profile_id)
          .single()
        profile = result.data
        profileError = result.error
      } else {
        profileError = err
      }
    }

    if (profileError || !profile) {
      return new Response(
        JSON.stringify({ success: false, error: 'Profile not found' }),
        { 
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    // Use auth_user_id if available, otherwise use id
    const authUserId = profile.auth_user_id || profile.id

    // Generate new password
    const newPassword = generatePassword(12)

    // Update password in auth.users
    const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(
      authUserId,
      { password: newPassword }
    )

    if (updateError) {
      console.error('Password update error:', updateError)
      return new Response(
        JSON.stringify({ success: false, error: updateError.message }),
        { 
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
        }
      )
    }

    await resend.emails.send({
      from: resendFromEmail,
      to: email,
      subject: 'Your password has been reset',
      html: `
        <p>Hi ${profile.full_name ?? 'there'},</p>
        <p>Your password was reset by an administrator.</p>
        <p>Email: ${email}</p>
        <p>New password: ${newPassword}</p>
        <p>Please sign in and change it immediately.</p>
      `,
    })

    return new Response(
      JSON.stringify({ 
        success: true, 
        message: 'Password regenerated successfully. Email sent.'
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ success: false, error: error instanceof Error ? error.message : 'An unexpected error occurred' }),
      { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' } 
      }
    )
  }
})

