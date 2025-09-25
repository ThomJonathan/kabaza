import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { Resend } from 'https://esm.sh/resend@0.0.10'; // Using Resend as an example

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Initialize Supabase client
const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const supabase = createClient(supabaseUrl, supabaseServiceKey);

// Initialize email service (using Resend as example)
const resendApiKey = Deno.env.get('RESEND_API_KEY')!;
const resend = new Resend(resendApiKey);

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const path = url.pathname;

    if (path.endsWith('/send-reset-token')) {
      const { email, token } = await req.json();

      if (!email || !token) {
        return new Response(
          JSON.stringify({ error: 'Email and token are required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Send email using Resend
      try {
        const { data, error } = await resend.emails.send({
          from: 'noreply@yourdomain.com', // Replace with your domain
          to: email,
          subject: 'Password Reset Code',
          html: `
            <h2>Password Reset Request</h2>
            <p>Your password reset code is: <strong>${token}</strong></p>
            <p>This code will expire in 15 minutes.</p>
            <p>If you didn't request this reset, please ignore this email.</p>
          `,
        });

        if (error) {
          console.error('Email sending error:', error);
          return new Response(
            JSON.stringify({ error: 'Failed to send email' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          );
        }

        console.log('Email sent successfully:', data);
        return new Response(
          JSON.stringify({ success: true, message: 'Reset token sent' }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

      } catch (emailError) {
        console.error('Email service error:', emailError);
        return new Response(
          JSON.stringify({ error: 'Email service unavailable' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

    } else if (path.endsWith('/update-user-password')) {
      // ... keep your existing password update logic
      const { email, newPassword } = await req.json();

      if (!email || !newPassword) {
        return new Response(
          JSON.stringify({ error: 'Email and new password are required' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Get user by email using admin API
      const { data: users, error: listError } = await supabase.auth.admin.listUsers();

      if (listError) {
        throw listError;
      }

      const user = users.users.find(u => u.email?.toLowerCase() === email.toLowerCase());

      if (!user) {
        return new Response(
          JSON.stringify({ error: 'User not found' }),
          { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
      }

      // Update user password using admin API
      const { error: updateError } = await supabase.auth.admin.updateUserById(
        user.id,
        { password: newPassword }
      );

      if (updateError) {
        throw updateError;
      }

      return new Response(
        JSON.stringify({ success: true, message: 'Password updated successfully' }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    } else {
      return new Response(
        JSON.stringify({ error: 'Endpoint not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
  } catch (error) {
    console.error('Error in function:', error);
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});