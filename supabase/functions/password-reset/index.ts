// supabase/functions/password-reset/index.ts

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

    const supabaseClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });

    const { action, email, token, newPassword } = await req.json()

    // ==================== SEND CODE ACTION ====================
    if (action === 'send-code') {
      const { data: { users }, error: userError } = await supabaseClient.auth.admin.listUsers()

      if (userError) {
        console.error('Error listing users:', userError)
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Error checking user existence'
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
          }
        )
      }

      const user = users.find(u => u.email?.toLowerCase() === email.toLowerCase())

      if (!user) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'No account found with this email address.'
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 404,
          }
        )
      }

      const resetCode = Math.floor(100000 + Math.random() * 900000).toString()
      const expiresAt = new Date()
      expiresAt.setMinutes(expiresAt.getMinutes() + 10)

      const { error: insertError } = await supabaseClient
        .from('password_reset_codes')
        .insert({
          email: email.toLowerCase(),
          code: resetCode,
          expires_at: expiresAt.toISOString(),
          used: false
        })

      if (insertError) {
        console.error('Insert error:', insertError)
        throw new Error(`Failed to store reset code: ${insertError.message}`)
      }

      const emailResult = await sendResetEmail(email, resetCode)

      if (!emailResult.emailSent) {
        console.error('Email send error:', emailResult.emailError)
        return new Response(
          JSON.stringify({
            success: false,
            error: `Failed to send email. ${emailResult.emailError}`
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
          }
        )
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Reset code sent successfully'
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        }
      )
    }

    // ==================== UPDATE PASSWORD ACTION ====================
    if (action === 'update-password') {
      const { data: codeData, error: codeError } = await supabaseClient
        .from('password_reset_codes')
        .select('*')
        .eq('email', email.toLowerCase())
        .eq('code', token)
        .eq('used', false)
        .single()

      if (codeError || !codeData) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Invalid or expired reset code'
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
          }
        )
      }

      const now = new Date()
      const expiresAt = new Date(codeData.expires_at)

      if (now > expiresAt) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Reset code has expired. Please request a new one.'
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 400,
          }
        )
      }

      const { data: { users }, error: userError } = await supabaseClient.auth.admin.listUsers()

      if (userError) {
        console.error('Error listing users:', userError)
        return new Response(
          JSON.stringify({
            success: false,
            error: 'Error finding user'
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500,
          }
        )
      }

      const user = users.find(u => u.email?.toLowerCase() === email.toLowerCase())

      if (!user) {
        return new Response(
          JSON.stringify({
            success: false,
            error: 'User not found'
          }),
          {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 404,
          }
        )
      }

      const { error: updateError } = await supabaseClient.auth.admin.updateUserById(
        user.id,
        { password: newPassword }
      )

      if (updateError) {
        console.error('Update password error:', updateError)
        throw new Error(`Failed to update password: ${updateError.message}`)
      }

      await supabaseClient
        .from('password_reset_codes')
        .update({ used: true })
        .eq('id', codeData.id)

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Password updated successfully'
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        }
      )
    }

    return new Response(
      JSON.stringify({
        success: false,
        error: 'Invalid action'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || 'An unexpected error occurred'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})

// ==================== EMAIL SENDING WITH RESEND ====================
async function sendResetEmail(email: string, code: string): Promise<{ emailSent: boolean, emailError?: string }> {
  try {
    const resendApiKey = Deno.env.get('RESEND_API_KEY')

    if (!resendApiKey) {
      throw new Error('RESEND_API_KEY not configured')
    }

    console.log('Sending email via Resend to:', email)

    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'QuickLift <onboarding@resend.dev>', // Use onboarding domain for testing
        to: email,
        subject: 'Reset Your Password - QuickLift',
        html: `
          <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
            <h2 style="color: #333;">Reset Your Password</h2>
            <p style="color: #666; font-size: 16px;">You requested to reset your password. Use the code below:</p>
            <div style="background-color: #f4f4f4; padding: 20px; text-align: center; margin: 30px 0; border-radius: 8px;">
              <div style="font-size: 36px; font-weight: bold; letter-spacing: 8px; color: #333;">
                ${code}
              </div>
            </div>
            <p style="color: #666; font-size: 14px;">This code will expire in 10 minutes.</p>
            <p style="color: #999; font-size: 12px; margin-top: 30px;">If you didn't request this, please ignore this email.</p>
          </div>
        `,
      }),
    })

    const data = await response.json()

    if (!response.ok) {
      console.error('Resend API error:', data)
      throw new Error(data.message || 'Failed to send email via Resend')
    }

    console.log('Email sent successfully via Resend:', data.id)
    return { emailSent: true }

  } catch (error) {
    console.error('Error sending email:', error)
    return {
      emailSent: false,
      emailError: error?.message || String(error)
    }
  }
}