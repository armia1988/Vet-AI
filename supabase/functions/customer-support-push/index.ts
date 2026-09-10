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

function shorten(value: unknown, max = 260): string {
  const text = String(value ?? '').trim()
  if (!text) return ''
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
    const messageId = String(body?.message_id ?? '').trim()
    if (!/^[0-9a-f-]{36}$/i.test(messageId)) {
      return new Response(JSON.stringify({ error: 'invalid_message_id' }), {
        status: 400,
        headers: jsonHeaders,
      })
    }

    const admin = createClient(env('SUPABASE_URL'), serviceKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: message, error: messageError } = await admin
      .from('support_messages')
      .select('id,thread_id,sender_id,sender_role,message,message_type,attachment_name,attachment_mime,created_at')
      .eq('id', messageId)
      .maybeSingle()
    if (messageError) throw messageError
    if (!message || message.sender_role !== 'support') {
      return new Response(JSON.stringify({ ok: true, skipped: 'not_support_message' }), {
        headers: jsonHeaders,
      })
    }

    const { data: thread, error: threadError } = await admin
      .from('support_threads')
      .select('id,farm_id')
      .eq('id', message.thread_id)
      .maybeSingle()
    if (threadError) throw threadError
    if (!thread) {
      return new Response(JSON.stringify({ ok: true, skipped: 'thread_not_found' }), {
        headers: jsonHeaders,
      })
    }

    const { data: devices, error: devicesError } = await admin
      .from('push_devices')
      .select('id,user_id,device_token,environment')
      .eq('farm_id', thread.farm_id)
      .eq('enabled', true)
      .eq('platform', 'ios')
    if (devicesError) throw devicesError
    if (!devices?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: 'no_registered_farm_devices' }), {
        headers: jsonHeaders,
      })
    }

    const type = String(message.message_type ?? '').toLowerCase()
    const mime = String(message.attachment_mime ?? '').toLowerCase()
    let text = shorten(message.message, 320)
    if (!text) {
      if (type === 'audio' || mime.startsWith('audio/')) text = 'Voice message'
      else if (type === 'location') text = 'Location'
      else if (mime.startsWith('image/')) text = 'Photo'
      else if (message.attachment_name) text = `Attachment: ${shorten(message.attachment_name, 180)}`
      else text = 'New support message'
    }

    const privateKey = await importPKCS8(cleanPrivateKey(env('APNS_PRIVATE_KEY')), 'ES256')
    const providerToken = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: env('APNS_KEY_ID') })
      .setIssuer(env('APNS_TEAM_ID'))
      .setIssuedAt()
      .sign(privateKey)

    const payload = JSON.stringify({
      aps: {
        alert: { title: 'Vet AI Support', body: text },
        sound: 'default',
        badge: 1,
        'interruption-level': 'active',
      },
      vet_ai: {
        type: 'support_message',
        message_id: message.id,
        thread_id: thread.id,
        farm_id: thread.farm_id,
      },
    })

    let sent = 0
    let failed = 0
    const results: Array<Record<string, unknown>> = []

    for (const device of devices) {
      const { data: delivery, error: deliveryError } = await admin
        .from('customer_support_push_deliveries')
        .insert({
          message_id: message.id,
          push_device_id: device.id,
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
            'content-type': 'application/json',
          },
          body: payload,
        },
      )

      const apnsId = response.headers.get('apns-id')
      if (response.ok) {
        sent++
        await admin.from('customer_support_push_deliveries').update({
          status: 'sent',
          sent_at: new Date().toISOString(),
          apns_id: apnsId,
          error: null,
        }).eq('id', delivery!.id)
        results.push({ device: device.id, sent: true, apns_id: apnsId })
      } else {
        failed++
        const responseBody: any = await response.json().catch(() => ({ reason: `HTTP_${response.status}` }))
        const reason = String(responseBody?.reason ?? `HTTP_${response.status}`)
        await admin.from('customer_support_push_deliveries').update({
          status: 'failed',
          error: reason,
          apns_id: apnsId,
        }).eq('id', delivery!.id)
        if (['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(reason)) {
          await admin.from('push_devices').update({
            enabled: false,
            updated_at: new Date().toISOString(),
          }).eq('id', device.id)
        }
        results.push({ device: device.id, sent: false, reason })
      }
    }

    return new Response(JSON.stringify({
      ok: failed === 0,
      message_id: message.id,
      sent,
      failed,
      results,
    }), { headers: jsonHeaders })
  } catch (error: unknown) {
    console.error('customer-support-push failed', error)
    return new Response(JSON.stringify({
      error: 'customer_support_push_failed',
      message: error instanceof Error ? error.message : String(error),
    }), { status: 500, headers: jsonHeaders })
  }
})
