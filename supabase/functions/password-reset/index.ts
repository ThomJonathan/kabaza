import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Initialize Supabase client with service role key
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('Missing Supabase environment variables');
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Brevo configuration
const brevoApiKey = Deno.env.get('BREVO_API_KEY');
const fromEmail = Deno.env.get('FROM_EMAIL') || 'no-reply@jaytech.com';
const fromName = Deno.env.get('FROM_NAME') || 'QUICKlift';

// Send email using Brevo API
async function sendResetEmail(email: string, token: string) {
  console.log('Attempting to send email to:', email);

  // Debug: Check if environment variables are loaded
  console.log('Environment check:', {
    brevoApiKey: brevoApiKey ? 'Present' : 'Missing',
    fromEmail: fromEmail,
    fromName: fromName
  });

  if (!brevoApiKey) {
    console.error('BREVO_API_KEY not configured');
    throw new Error('BREVO_API_KEY not configured');
  }

  // Validate email format
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(email)) {
    throw new Error('Invalid email format');
  }

  // Validate sender email format
  if (!emailRegex.test(fromEmail)) {
    throw new Error('Invalid sender email format');
  }

  const emailPayload = {
    sender: {
      email: fromEmail,
      name: fromName
    },
    to: [{ email: email }],
    subject: 'Password Reset Code - QUICKlift',
    htmlContent: `
      <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
        <h2 style="color: #333; text-align: center;">Password Reset Request</h2>
        <p>Hello,</p>
        <p>You requested to reset your password for your QUICKlift account.</p>
        <div style="background-color: #f5f5f5; padding: 20px; text-align: center; margin: 20px 0;">
          <h3 style="margin: 0; color: #333;">Your Reset Code:</h3>
          <p style="font-size: 32px; font-weight: bold; color: #007bff; margin: 10px 0; letter-spacing: 2px;">${token}</p>
        </div>
        <p><strong>This code will expire in 15 minutes.</strong></p>
        <p>If you didn't request this reset, please ignore this email and your password will remain unchanged.</p>
        <hr style="margin: 30px 0;">
        <p style="color: #666; font-size: 12px;">
          This is an automated message from QUICKlift. Please do not reply to this email.
        </p>
      </div>
    `,
  };

  console.log('Email payload prepared:', {
    sender: emailPayload.sender,
    to: emailPayload.to,
    subject: emailPayload.subject
  });

  try {
    const response = await fetch('https://api.brevo.com/v3/smtp/email', {
      method: 'POST',
      headers: {
        'api-key': brevoApiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(emailPayload),
    });

    console.log('Brevo API response status:', response.status);
    console.log('Brevo API response headers:', Object.fromEntries(response.headers));

    const responseText = await response.text();
    console.log('Brevo API raw response:', responseText);

    if (!response.ok) {
      console.error('Brevo API error details:', {
        status: response.status,
        statusText: response.statusText,
        body: responseText
      });
      throw new Error(`Brevo API error: ${response.status} - ${responseText}`);
    }

    let result;
    try {
      result = JSON.parse(responseText);
    } catch (parseError) {
      console.error('Failed to parse Brevo response as JSON:', parseError);
      throw new Error('Invalid JSON response from Brevo API');
    }

    console.log('Email sent successfully:', result);
    return result;

  } catch (error) {
    console.error('Detailed error in sendResetEmail:', {
      name: error.name,
      message: error.message,
      stack: error.stack
    });
    throw error;
  }
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Parse the request body
    let body;
    try {
      body = await req.json();
    } catch (parseError) {
      console.error('JSON parse error:', parseError);
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid JSON in request body' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    const { action, email, token, newPassword } = body;
    console.log('Received request:', { action, email, token: token ? '***' : 'missing' });

    // Route: Send reset token
    if (action === 'send-reset-token') {
      if (!email || !token) {
        console.error('Missing email or token');
        return new Response(
          JSON.stringify({ success: false, error: 'Email and token are required' }),
          {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      try {
        // Send email
        const emailResult = await sendResetEmail(email, token);
        console.log('Email sent successfully to:', email);

        return new Response(
          JSON.stringify({
            success: true,
            message: 'Reset code sent to your email!',
            emailId: emailResult.messageId
          }),
          {
            status: 200,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );

      } catch (emailError) {
        console.error('Email sending error details:', {
          name: emailError.name,
          message: emailError.message,
          stack: emailError.stack
        });

        // Return more specific error message
        let errorMessage = 'Failed to send reset email. Please try again.';
        if (emailError.message.includes('BREVO_API_KEY not configured')) {
          errorMessage = 'Email service not configured properly';
        } else if (emailError.message.includes('Invalid email format')) {
          errorMessage = 'Invalid email address';
        } else if (emailError.message.includes('Brevo API error')) {
          errorMessage = 'Email service temporarily unavailable';
        }

        return new Response(
          JSON.stringify({
            success: false,
            error: errorMessage,
            details: emailError.message // Include for debugging
          }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }
    }

    // Route: Update user password
    else if (action === 'update-password') {
      if (!email || !newPassword) {
        return new Response(
          JSON.stringify({ success: false, error: 'Email and new password are required' }),
          {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      // Validate password strength
      if (newPassword.length < 8) {
        return new Response(
          JSON.stringify({ success: false, error: 'Password must be at least 8 characters long' }),
          {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      // Get user by email using admin API
      const { data: users, error: listError } = await supabase.auth.admin.listUsers();

      if (listError) {
        console.error('Error listing users:', listError);
        return new Response(
          JSON.stringify({ success: false, error: 'Failed to find user' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      const user = users.users.find(u => u.email?.toLowerCase() === email.toLowerCase());

      if (!user) {
        return new Response(
          JSON.stringify({ success: false, error: 'User not found' }),
          {
            status: 404,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      // Update user password using admin API
      const { error: updateError } = await supabase.auth.admin.updateUserById(
        user.id,
        { password: newPassword }
      );

      if (updateError) {
        console.error('Error updating password:', updateError);
        return new Response(
          JSON.stringify({ success: false, error: 'Failed to update password' }),
          {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' }
          }
        );
      }

      return new Response(
        JSON.stringify({
          success: true,
          message: 'Password updated successfully'
        }),
        {
          status: 200,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    // Invalid action
    else {
      return new Response(
        JSON.stringify({ success: false, error: 'Invalid action. Use "send-reset-token" or "update-password"' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

  } catch (error) {
    console.error('Unexpected error in function:', {
      name: error.name,
      message: error.message,
      stack: error.stack
    });
    return new Response(
      JSON.stringify({
        success: false,
        error: 'Internal server error',
        details: error.message
      }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});