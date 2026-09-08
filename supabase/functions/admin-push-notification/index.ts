import { createClient } from 'npm:@supabase/supabase-js@2'
import { importPKCS8, SignJWT } from 'npm:jose@5'

const jsonHeaders = { 'Content-Type': 'application/json' }

function env(name: string): string {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new Error(`Missing ${name}`)
  return value
}

function cleanPrivateKey(value: string): string {
  return value.replace(/\\n/g, '\n').trim()
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

function soundForSeverity(severity: unknown): string {
  const value = String(severity ?? '').trim().toLowerCase()
  if (value === 'red') return 'vet_ai_red_trtr_alert.caf'
  if (value === 'orange') return 'vet_ai_orange_alert.caf'
  return 'default'
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405, headers: jsonHeaders })
  }

  try {
    const authorization = req.headers.get('Authorization') ?? ''
    if (!authorization.toLowerCase().startsWith('bearer ')) {
      return new Response(JSON.stringify({ error: 'missing_authorization' }), { status: 401, headers: jsonHeaders })
    }

    const url = env('SUPABASE_URL')
    const userClient = createClient(url, env('SUPABASE_ANON_KEY'), {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) {
      return new Response(JSON.stringify({ error: 'invalid_session' }), { status: 401, headers: jsonHeaders })
    }

    const admin = createClient(url, serviceKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: adminAccount, error: adminError } = await admin
      .from('admin_accounts')
      .select('role,active,permissions')
      .eq('user_id', userData.user.id)
      .maybeSingle()
    if (adminError) throw adminError
    if (!adminAccount?.active) {
      return new Response(JSON.stringify({ error: 'admin_required' }), { status: 403, headers: jsonHeaders })
    }
    const allowed = ['super_admin', 'admin'].includes(adminAccount.role) || adminAccount.permissions?.notifications === true
    if (!allowed) {
      return new Response(JSON.stringify({ error: 'notification_permission_required' }), { status: 403, headers: jsonHeaders })
    }

    const body = await req.json().catch(() => ({}))
    const notificationId = String(body?.notification_id ?? '').trim()
    if (!/^[0-9a-f-]{36}$/i.test(notificationId)) {
      return new Response(JSON.stringify({ error: 'invalid_notification_id' }), { status: 400, headers: jsonHeaders })
    }

    const { data: notification, error: notificationError } = await admin
      .from('admin_notifications')
      .select('*')
      .eq('id', notificationId)
      .maybeSingle()
    if (notificationError) throw notificationError
    if (!notification) {
      return new Response(JSON.stringify({ error: 'notification_not_found' }), { status: 404, headers: jsonHeaders })
    }

    let devicesQuery = admin
      .from('push_devices')
      .select('id,user_id,farm_id,device_token,environment')
      .eq('enabled', true)
      .eq('platform', 'ios')

    if (notification.target_scope === 'farm') {
      if (!notification.farm_id) throw new Error('farm_target_missing')
      devicesQuery = devicesQuery.eq('farm_id', notification.farm_id)
    } else if (notification.target_scope === 'user') {
      if (!notification.user_id) throw new Error('user_target_missing')
      devicesQuery = devicesQuery.eq('user_id', notification.user_id)
    } else if (notification.target_scope !== 'all') {
      throw new Error('unsupported_target_scope')
    }

    const { data: devices, error: devicesError } = await devicesQuery
    if (devicesError) throw devicesError

    if (!devices?.length) {
      await admin.from('admin_notifications').update({
        status: 'sent',
        sent_count: 0,
        failed_count: 0,
        sent_at: new Date().toISOString(),
      }).eq('id', notification.id)
      return new Response(JSON.stringify({ ok: true, sent: 0, failed: 0, reason: 'no_target_devices' }), { headers: jsonHeaders })
    }

    const apnsKeyId = env('APNS_KEY_ID')
    const apnsTeamId = env('APNS_TEAM_ID')
    const apnsBundleId = env('APNS_BUNDLE_ID')
    const privateKey = await importPKCS8(cleanPrivateKey(env('APNS_PRIVATE_KEY')), 'ES256')
    const providerToken = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: apnsKeyId })
      .setIssuer(apnsTeamId)
      .setIssuedAt()
      .sign(privateKey)

    const sound = soundForSeverity(notification.severity)
    const payload = JSON.stringify({
      aps: {
        alert: { title: String(notification.title).slice(0, 140), body: String(notification.body).slice(0, 900) },
        sound,
        badge: 1,
      },
      vet_ai: {
        type: 'admin_notification',
        notification_id: notification.id,
        severity: notification.severity,
        farm_id: notification.farm_id,
      },
    })

    let sent = 0
    let failed = 0
    const failures: Array<Record<string, unknown>> = []

    for (const device of devices) {
      const host = device.environment === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com'
      const response = await fetch(`https://${host}/3/device/${encodeURIComponent(device.device_token)}`, {
        method: 'POST',
        headers: {
          authorization: `bearer ${providerToken}`,
          'apns-topic': apnsBundleId,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'apns-collapse-id': notification.id,
          'content-type': 'application/json',
        },
        body: payload,
      })

      if (response.ok) {
        sent++
      } else {
        failed++
        const result = await response.json().catch(() => ({ reason: `HTTP_${response.status}` }))
        const reason = String(result?.reason ?? `HTTP_${response.status}`)
        failures.push({ device_id: device.id, reason })
        if (['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(reason)) {
          await admin.from('push_devices').update({ enabled: false, updated_at: new Date().toISOString() }).eq('id', device.id)
        }
      }
    }

    const status = failed === 0 ? 'sent' : sent > 0 ? 'partial' : 'failed'
    await admin.from('admin_notifications').update({
      status,
      sent_count: sent,
      failed_count: failed,
      sent_at: new Date().toISOString(),
    }).eq('id', notification.id)

    return new Response(JSON.stringify({ ok: failed === 0, notification_id: notification.id, sent, failed, status, sound, failures }), { headers: jsonHeaders })
  } catch (error) {
    console.error('admin-push-notification failed', error)
    return new Response(JSON.stringify({ error: 'admin_push_failed', message: String(error?.message ?? error) }), { status: 500, headers: jsonHeaders })
  }
})
