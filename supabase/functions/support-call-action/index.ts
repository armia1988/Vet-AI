import { createClient } from 'npm:@supabase/supabase-js@2'

const headers = { 'Content-Type': 'application/json' }

function env(name: string): string {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new Error(`Missing ${name}`)
  return value
}

function serviceKey(): string {
  const modern = Deno.env.get('SUPABASE_SECRET_KEYS')
  if (modern) {
    try {
      const keys = JSON.parse(modern)
      if (keys?.default) return keys.default
    } catch (_) {}
  }
  return env('SUPABASE_SERVICE_ROLE_KEY')
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405, headers })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const callId = String(body?.call_id ?? '').trim()
    const roomKey = String(body?.room_key ?? '').trim()
    const action = String(body?.action ?? '').trim().toLowerCase()

    if (!/^[0-9a-f-]{36}$/i.test(callId) || !/^[0-9a-f]{36}$/i.test(roomKey)) {
      return new Response(JSON.stringify({ error: 'invalid_call_capability' }), { status: 400, headers })
    }
    if (!['accept', 'decline', 'end'].includes(action)) {
      return new Response(JSON.stringify({ error: 'invalid_action' }), { status: 400, headers })
    }

    const admin = createClient(env('SUPABASE_URL'), serviceKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: call, error } = await admin
      .from('support_calls')
      .select('id,status,room_key,created_at')
      .eq('id', callId)
      .maybeSingle()
    if (error) throw error
    if (!call || String(call.room_key) !== roomKey) {
      return new Response(JSON.stringify({ error: 'call_not_authorized' }), { status: 403, headers })
    }

    if (action === 'accept') {
      const created = Date.parse(String(call.created_at ?? ''))
      if (call.status !== 'ringing' || !Number.isFinite(created) || Date.now() - created > 90_000) {
        return new Response(JSON.stringify({ ok: true, skipped: 'call_not_ringing' }), { headers })
      }
      const { error: updateError } = await admin
        .from('support_calls')
        .update({ status: 'accepted', answered_at: new Date().toISOString() })
        .eq('id', callId)
        .eq('status', 'ringing')
      if (updateError) throw updateError
    } else {
      const status = action === 'decline' ? 'declined' : 'ended'
      const { error: updateError } = await admin
        .from('support_calls')
        .update({ status, ended_at: new Date().toISOString() })
        .eq('id', callId)
        .in('status', ['ringing', 'accepted'])
      if (updateError) throw updateError
    }

    return new Response(JSON.stringify({ ok: true, call_id: callId, action }), { headers })
  } catch (error: unknown) {
    console.error('support-call-action failed', error)
    return new Response(
      JSON.stringify({ error: 'support_call_action_failed', message: error instanceof Error ? error.message : String(error) }),
      { status: 500, headers },
    )
  }
})
