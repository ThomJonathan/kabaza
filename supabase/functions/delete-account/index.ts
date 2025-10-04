import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  try {
    // Create Supabase client with service role key
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

    // Get user from JWT
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: userError } = await supabaseAdmin.auth.getUser(token)

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token or user not found' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Deleting account for user: ${user.id}`)

    // Step 1: Update public.users and delete related data (except ride_requests)
    const { data: dbResult, error: dbError } = await supabaseAdmin
      .rpc('delete_user_account', { p_user_id: user.id })

    if (dbError || !dbResult?.success) {
      console.error('Database deletion error:', dbError || dbResult?.error)
      return new Response(
        JSON.stringify({
          error: 'Failed to delete user data from database',
          details: dbError?.message || dbResult?.error
        }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    console.log(`Deleted ${dbResult.user_role} account data from database`)

    // Step 2: Delete from auth.users (THIS FREES UP THE EMAIL!)
    const { error: authDeleteError } = await supabaseAdmin.auth.admin.deleteUser(user.id)

    if (authDeleteError) {
      console.error('Auth deletion error:', authDeleteError)
      return new Response(
        JSON.stringify({ error: 'Failed to delete auth user' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    console.log(`✅ Successfully deleted account for user: ${user.id} (${dbResult.user_role})`)

    return new Response(
      JSON.stringify({
        success: true,
        message: 'Account deleted successfully',
        user_id: user.id,
        user_role: dbResult.user_role
      }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Unexpected error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})