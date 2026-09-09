import { createClient } from 'npm:@supabase/supabase-js@2'
import { importPKCS8, SignJWT } from 'npm:jose@5'

const jsonHeaders = { 'Content-Type': 'application/json' }

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

function cleanPrivateKey(value: string): string {
  return value.replace(/\\n/g, '\n').trim()
}

function cleanText(value: unknown, fallback: string, max = 72): string {
  const text = String(value ?? '').trim() || fallback
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), {
      status: 405,
      headers: jsonHeaders,
    })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const callId = String(body?.call_id ?? '').trim()
    if (!/^[0-9a-f-]{36}$/i.test(callId)) {
      return new Response(JSON.stringify({ error: 'invalid_call_id' }), {
        status: 400,
        headers: jsonHeaders,
      })
    }

    const admin = createClient(env('SUPABASE_URL'), serviceKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: call, error: callError } = await admin
      .from('support_calls')
      .select('id,thread_id,initiated_by,caller_role,call_type,status,created_at')
      .eq('id', callId)
      .maybeSingle()
    if (callError) throw callError
    if (!call || call.status !== 'ringing') {
      return new Response(JSON.stringify({ ok: true, skipped: 'not_ringing' }), {
        headers: jsonHeaders,
      })
    }

    const createdAt = Date.parse(String(call.created_at ?? ''))
    if (!Number.isFinite(createdAt) || Date.now() - createdAt > 90_000) {
      return new Response(JSON.stringify({ ok: true, skipped: 'stale_call' }), {
        headers: jsonHeaders,
      })
    }

    const { data: thread, error: threadError } = await admin
      .from('support_threads')
      .select('id,farm_id')
      .eq('id', call.thread_id)
      .maybeSingle()
    if (threadError) throw threadError
    if (!thread) {
      return new Response(JSON.stringify({ ok: true, skipped: 'thread_not_found' }), {
        headers: jsonHeaders,
      })
    }

    const [{ data: farm }, { data: callerProfile }] = await Promise.all([
      admin
        .from('farms')
        .select('farm_name,company_name')
        .eq('id', thread.farm_id)
        .maybeSingle(),
      admin
        .from('profiles')
        .select('full_name')
        .eq('id', call.initiated_by)
        .maybeSingle(),
    ])

    const recipientDevices: Array<{
      id: string
      user_id: string
      device_token: string
      environment: string
      scope: 'admin' | 'farm'
    }> = []

    if (call.caller_role === 'user') {
      const { data: accounts, error: accountsError } = await admin
        .from('admin_accounts')
        .select('user_id,role,permissions')
        .eq('active', true)
      if (accountsError) throw accountsError

      const supportIds = (accounts ?? [])
        .filter((row: any) =>
          ['super_admin', 'admin', 'support'].includes(String(row.role)) ||
          row.permissions?.support === true
        )
        .map((row: any) => String(row.user_id))
        .filter((id: string) => id && id !== String(call.initiated_by))

      if (supportIds.length) {
        const { data: devices, error: devicesError } = await admin
          .from('admin_push_devices')
          .select('id,user_id,device_token,environment')
          .in('user_id', supportIds)
          .eq('enabled', true)
          .eq('platform', 'ios')
        if (devicesError) throw devicesError
        for (const device of devices ?? []) {
          recipientDevices.push({ ...device, scope: 'admin' })
        }
      }
    } else {
      const { data: devices, error: devicesError } = await admin
        .from('push_devices')
        .select('id,user_id,device_token,environment')
        .eq('farm_id', thread.farm_id)
        .eq('enabled', true)
        .eq('platform', 'ios')
        .neq('user_id', call.initiated_by)
      if (devicesError) throw devicesError
      for (const device of devices ?? []) {
        recipientDevices.push({ ...device, scope: 'farm' })
      }
    }

    if (!recipientDevices.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: 'no_devices' }), {
        headers: jsonHeaders,
      })
    }

    const privateKey = await importPKCS8(cleanPrivateKey(env('APNS_PRIVATE_KEY')), 'ES256')
    const providerToken = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: env('APNS_KEY_ID') })
      .setIssuer(env('APNS_TEAM_ID'))
      .setIssuedAt()
      .sign(privateKey)

    const farmName = cleanText(farm?.farm_name || farm?.company_name, 'Customer farm')
    const callerName = cleanText(callerProfile?.full_name, call.caller_role === 'user' ? farmName : 'Vet AI Support')
    const video = call.call_type === 'video'
    const title = call.caller_role === 'user'
      ? `📞 ${farmName}`
      : '📞 Vet AI Support'
    const notificationBody = video
      ? `${callerName} is starting a video call`
      : `${callerName} is calling you`

    const payload = JSON.stringify({
      aps: {
        alert: { title, body: notificationBody },
        sound: 'vet_ai_incoming_call.caf',
        badge: 1,
        'interruption-level': 'time-sensitive',
      },
      vet_ai: {
        type: 'support_call',
        call_id: call.id,
        thread_id: call.thread_id,
        farm_id: thread.farm_id,
        call_type: call.call_type,
        caller_role: call.caller_role,
      },
    })

    let sent = 0
    let failed = 0
    const results: Array<Record<string, unknown>> = []

    for (const device of recipientDevices) {
      const { data: delivery, error: deliveryError } = await admin
        .from('support_call_push_deliveries')
        .insert({
          call_id: call.id,
          device_scope: device.scope,
          device_id: device.id,
          recipient_user_id: device.user_id,
          status: 'sending',
        })
        .select('id')
        .maybeSingle()

      if (deliveryError) {
        if (deliveryError.code === '23505') {
          results.push({ device: device.id, skipped: 'already_dispatched' })
          continue
        }
        throw deliveryError
      }

      const host = device.environment === 'sandbox'
        ? 'api.sandbox.push.apple.com'
        : 'api.push.apple.com'
      const response = await fetch(
        `https://${host}/3/device/${encodeURIComponent(device.device_token)}`,
        {
          method: 'POST',
          headers: {
            authorization: `bearer ${providerToken}`,
            'apns-topic': env('APNS_BUNDLE_ID'),
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'apns-expiration': String(Math.floor(Date.now() / 1000) + 75),
            'apns-collapse-id': `vet-ai-call-${call.id}`,
            'content-type': 'application/json',
          },
          body: payload,
        },
      )

      const apnsId = response.headers.get('apns-id')
      if (response.ok) {
        sent++
        await admin
          .from('support_call_push_deliveries')
          .update({
            status: 'sent',
            sent_at: new Date().toISOString(),
            apns_id: apnsId,
            error: null,
          })
          .eq('id', delivery!.id)
        results.push({ device: device.id, sent: true, apns_id: apnsId })
      } else {
        failed++
        const responseBody: any = await response
          .json()
          .catch(() => ({ reason: `HTTP_${response.status}` }))
        const reason = String(responseBody?.reason ?? `HTTP_${response.status}`)
        await admin
          .from('support_call_push_deliveries')
          .update({ status: 'failed', error: reason, apns_id: apnsId })
          .eq('id', delivery!.id)

        if (['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(reason)) {
          const table = device.scope === 'admin' ? 'admin_push_devices' : 'push_devices'
          await admin
            .from(table)
            .update({ enabled: false, updated_at: new Date().toISOString() })
            .eq('id', device.id)
        }
        results.push({ device: device.id, sent: false, reason })
      }
    }

    return new Response(
      JSON.stringify({ ok: failed === 0, call_id: call.id, sent, failed, results }),
      { headers: jsonHeaders },
    )
  } catch (error: unknown) {
    console.error('support-call-push failed', error)
    const message = error instanceof Error ? error.message : String(error)
    return new Response(
      JSON.stringify({ error: 'support_call_push_failed', message }),
      { status: 500, headers: jsonHeaders },
    )
  }
})
