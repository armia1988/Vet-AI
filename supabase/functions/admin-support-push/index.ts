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

function shorten(value: unknown, max = 220): string {
  const text = String(value ?? '').trim()
  if (!text) return ''
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405, headers: jsonHeaders })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const messageId = String(body?.message_id ?? '').trim()
    if (!/^[0-9a-f-]{36}$/i.test(messageId)) {
      return new Response(JSON.stringify({ error: 'invalid_message_id' }), { status: 400, headers: jsonHeaders })
    }

    const admin = createClient(env('SUPABASE_URL'), serviceKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: message, error: messageError } = await admin
      .from('support_messages')
      .select('id,thread_id,sender_id,sender_role,message,attachment_name,created_at')
      .eq('id', messageId)
      .maybeSingle()
    if (messageError) throw messageError
    if (!message || message.sender_role !== 'user') {
      return new Response(JSON.stringify({ ok: true, skipped: 'not_customer_message' }), { headers: jsonHeaders })
    }

    const { data: thread, error: threadError } = await admin
      .from('support_threads')
      .select('id,farm_id,subject')
      .eq('id', message.thread_id)
      .maybeSingle()
    if (threadError) throw threadError
    if (!thread) return new Response(JSON.stringify({ ok: true, skipped: 'thread_not_found' }), { headers: jsonHeaders })

    const { data: farm } = await admin
      .from('farms')
      .select('farm_name,company_name')
      .eq('id', thread.farm_id)
      .maybeSingle()
    const { data: sender } = await admin
      .from('profiles')
      .select('full_name')
      .eq('id', message.sender_id)
      .maybeSingle()

    const { data: adminAccounts, error: accountsError } = await admin
      .from('admin_accounts')
      .select('user_id,role,active,permissions')
      .eq('active', true)
    if (accountsError) throw accountsError

    const recipientIds = (adminAccounts ?? [])
      .filter((row: any) => ['super_admin', 'admin', 'support'].includes(String(row.role)) || row.permissions?.support === true)
      .map((row: any) => String(row.user_id))
    if (!recipientIds.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: 'no_support_admins' }), { headers: jsonHeaders })
    }

    const { data: devices, error: devicesError } = await admin
      .from('admin_push_devices')
      .select('id,user_id,device_token,environment')
      .in('user_id', recipientIds)
      .eq('enabled', true)
      .eq('platform', 'ios')
    if (devicesError) throw devicesError
    if (!devices?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: 'no_admin_devices' }), { headers: jsonHeaders })
    }

    const privateKey = await importPKCS8(cleanPrivateKey(env('APNS_PRIVATE_KEY')), 'ES256')
    const providerToken = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: env('APNS_KEY_ID') })
      .setIssuer(env('APNS_TEAM_ID'))
      .setIssuedAt()
      .sign(privateKey)

    const farmName = shorten(farm?.farm_name || farm?.company_name || 'Customer farm', 70)
    const senderName = shorten(sender?.full_name || 'Customer', 60)
    const text = shorten(message.message || (message.attachment_name ? `Attachment: ${message.attachment_name}` : 'New support message'), 320)
    const title = `💬 Vet AI Support — ${farmName}`
    const notificationBody = `${senderName}: ${text}`
    const payload = JSON.stringify({
      aps: {
        alert: { title, body: notificationBody },
        sound: 'default',
        badge: 1,
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
        .from('admin_support_push_deliveries')
        .insert({ message_id: message.id, admin_push_device_id: device.id, status: 'sending' })
        .select('id')
        .maybeSingle()

      if (deliveryError) {
        if (deliveryError.code === '23505') {
          results.push({ device: device.id, skipped: 'already_dispatched' })
          continue
        }
        throw deliveryError
      }

      const host = device.environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'
      const response = await fetch(`https://${host}/3/device/${encodeURIComponent(device.device_token)}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${providerToken}`,
          'apns-topic': env('APNS_BUNDLE_ID'),
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'content-type': 'application/json',
        },
        body: payload,
      })

      const apnsId = response.headers.get('apns-id')
      if (response.ok) {
        sent++
        await admin.from('admin_support_push_deliveries').update({
          status: 'sent', sent_at: new Date().toISOString(), apns_id: apnsId, error: null,
        }).eq('id', delivery!.id)
        results.push({ device: device.id, sent: true, apns_id: apnsId })
      } else {
        failed++
        const responseBody: any = await response.json().catch(() => ({ reason: `HTTP_${response.status}` }))
        const reason = String(responseBody?.reason ?? `HTTP_${response.status}`)
        await admin.from('admin_support_push_deliveries').update({ status: 'failed', error: reason, apns_id: apnsId }).eq('id', delivery!.id)
        if (['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(reason)) {
          await admin.from('admin_push_devices').update({ enabled: false, updated_at: new Date().toISOString() }).eq('id', device.id)
        }
        results.push({ device: device.id, sent: false, reason })
      }
    }

    return new Response(JSON.stringify({ ok: failed === 0, message_id: message.id, sent, failed, results }), { headers: jsonHeaders })
  } catch (error: unknown) {
    console.error('admin-support-push failed', error)
    const message = error instanceof Error ? error.message : String(error)
    return new Response(JSON.stringify({ error: 'admin_support_push_failed', message }), { status: 500, headers: jsonHeaders })
  }
})
