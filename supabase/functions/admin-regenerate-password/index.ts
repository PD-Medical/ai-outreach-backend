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
    const body = await req.json()
    console.log('Regenerate password request body:', JSON.stringify(body))

    const profileIdInput = typeof body.profile_id === 'string' ? body.profile_id.trim() : ''
    const authUserIdInput = typeof (body.auth_user_id ?? body.user_id) === 'string'
      ? (body.auth_user_id ?? body.user_id).trim()
      : ''
    const emailInput = typeof body.email === 'string' ? body.email.trim().toLowerCase() : ''

    if (!profileIdInput && !authUserIdInput && !emailInput) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Missing required identifier: profile_id, auth_user_id, or email must be provided.',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Fetch profile record flexibly (profile_id or id)
    let profile: any = null
    let profileError: any = null

    const fetchProfileByColumn = async (column: 'profile_id' | 'auth_user_id', value: string) => {
      return supabaseAdmin
        .from('profiles')
        .select('profile_id, auth_user_id, full_name')
        .eq(column, value)
        .maybeSingle()
    }

    const attempts: Array<[ 'profile_id' | 'auth_user_id', string ]> = []
    if (profileIdInput) {
      attempts.push(['profile_id', profileIdInput])
    }
    if (authUserIdInput) {
      attempts.push(['auth_user_id', authUserIdInput])
    }

    for (const [column, value] of attempts) {
      const result = await fetchProfileByColumn(column, value)
      if (result.error) {
        if (result.error?.message?.includes('profile_id') || result.error?.code === '42703') {
          // Column doesn't exist, skip
          continue
        }
        profileError = result.error
        break
      }
      if (result.data) {
        profile = result.data
        break
      }
    }

    if (!profile && !profileError && emailInput) {
      // As a last resort, try to find profile via auth user email
      const list = await supabaseAdmin.auth.admin.listUsers()
      if (list.error) {
        profileError = list.error
      } else {
        const userMatch = list.data.users.find((u) => u.email?.toLowerCase() === emailInput)
        if (userMatch) {
          const fallback = await fetchProfileByColumn('auth_user_id', userMatch.id)
          profile = fallback.data
          profileError = fallback.error
          if (!profile) {
            profile = { profile_id: userMatch.id, auth_user_id: userMatch.id, full_name: userMatch.user_metadata?.full_name }
          }
        }
      }
    }

    if (profileError) {
      console.error('Profile lookup error:', profileError)
      return new Response(
        JSON.stringify({
          success: false,
          error: `Failed to load profile: ${profileError.message ?? 'Unknown error'}`,
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    if (!profile) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Profile not found for supplied identifiers.',
          identifiers: { profile_id: profileIdInput, auth_user_id: authUserIdInput, email: emailInput },
        }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    const authUserId = profile.auth_user_id || authUserIdInput || profile.profile_id
    if (!authUserId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Profile is missing auth_user_id; cannot reset password.',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Generate new password
    const newPassword = generatePassword(12)

    // Update password in auth.users
    const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(authUserId, {
      password: newPassword,
    })

    if (updateError) {
      console.error('Password update error:', updateError)
      return new Response(
        JSON.stringify({ success: false, error: updateError.message }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Determine destination email
    let emailToSend = emailInput
    if (!emailToSend) {
      const { data: userInfo, error: userError } = await supabaseAdmin.auth.admin.getUserById(authUserId)
      if (userError) {
        console.error('Failed to fetch user email:', userError)
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Password updated but failed to fetch user email for notification.',
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          }
        )
      }
      emailToSend = userInfo.user?.email ?? ''
    }

    if (!emailToSend) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Password updated but no email address is available to send the new password.',
        }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    await resend.emails.send({
      from: resendFromEmail,
      to: emailToSend,
      subject: 'Your password has been reset',
      html: `
        <p>Hi ${profile.full_name ?? 'there'},</p>
        <p>Your password was reset by an administrator.</p>
        <p>Email: ${emailToSend}</p>
        <p>New password: ${newPassword}</p>
        <p>Please sign in and change it immediately.</p>
      `,
    })

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Password regenerated successfully. Email sent.',
        email: emailToSend,
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

