import { createClient } from 'npm:@supabase/supabase-js@2'
import { importPKCS8, SignJWT } from 'npm:jose@5'

const jsonHeaders = { 'Content-Type': 'application/json' }

function env(name: string): string {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new Error(`Missing ${name}`)
  return value
}

function adminKey(): string {
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

function truncate(value: unknown, max = 700): string {
  const text = String(value ?? '').trim()
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`
}

function soundForRisk(risk: unknown): string {
  const value = String(risk ?? '').trim().toLowerCase()
  if (value === 'red') return 'vet_ai_red_trtr_alert.caf'
  if (value === 'orange') return 'vet_ai_orange_alert.caf'
  return 'default'
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405, headers: jsonHeaders })
  }

  try {
    const body = await req.json().catch(() => ({}))
    const alertId = String(body?.alert_id ?? '').trim()
    if (!/^[0-9a-f-]{36}$/i.test(alertId)) {
      return new Response(JSON.stringify({ error: 'invalid_alert_id' }), { status: 400, headers: jsonHeaders })
    }

    const supabase = createClient(env('SUPABASE_URL'), adminKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: pushSetting } = await supabase
      .from('admin_system_settings')
      .select('value')
      .eq('key', 'sensor_alert_push_enabled')
      .maybeSingle()
    if (pushSetting?.value === false) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: 'sensor_alert_push_disabled' }), { headers: jsonHeaders })
    }

    const { data: alert, error: alertError } = await supabase
      .from('alerts')
      .select('id,farm_id,animal_id,risk,title,details,source,metric,threshold_text,value_numeric,created_at')
      .eq('id', alertId)
      .maybeSingle()

    if (alertError) throw alertError
    if (!alert) return new Response(JSON.stringify({ ok: true, skipped: 'alert_not_found' }), { headers: jsonHeaders })

    const { data: devices, error: devicesError } = await supabase
      .from('push_devices')
      .select('id,device_token,environment')
      .eq('farm_id', alert.farm_id)
      .eq('enabled', true)
      .eq('platform', 'ios')

    if (devicesError) throw devicesError
    if (!devices?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: 'no_registered_devices' }), { headers: jsonHeaders })
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

    const title = truncate(alert.title || 'Vet AI health alert', 140)
    const details = truncate(alert.details || alert.threshold_text || 'A new Vet AI health alert needs your attention.', 700)
    const alertSound = soundForRisk(alert.risk)
    const payload = JSON.stringify({
      aps: {
        alert: { title, body: details },
        sound: alertSound,
        badge: 1,
      },
      vet_ai: {
        alert_id: alert.id,
        farm_id: alert.farm_id,
        animal_id: alert.animal_id,
        risk: alert.risk,
        source: alert.source,
        metric: alert.metric,
        sound: alertSound,
      },
    })

    const results: Array<Record<string, unknown>> = []
    for (const device of devices) {
      const { data: delivery, error: deliveryError } = await supabase
        .from('push_deliveries')
        .insert({ alert_id: alert.id, push_device_id: device.id, status: 'sending' })
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
          'apns-topic': apnsBundleId,
          'apns-push-type': 'alert',
          'apns-priority': '10',
          'content-type': 'application/json',
        },
        body: payload,
      })

      const apnsId = response.headers.get('apns-id')
      let responseBody: any = null
      if (!response.ok) {
        responseBody = await response.json().catch(() => ({ reason: `HTTP_${response.status}` }))
      }

      if (response.ok) {
        await supabase.from('push_deliveries').update({ status: 'sent', sent_at: new Date().toISOString(), apns_id: apnsId, error: null }).eq('id', delivery!.id)
        results.push({ device: device.id, status: response.status, apns_id: apnsId, sound: alertSound })
      } else {
        const reason = String(responseBody?.reason ?? `HTTP_${response.status}`)
        await supabase.from('push_deliveries').update({ status: 'failed', error: reason, apns_id: apnsId }).eq('id', delivery!.id)
        if (['BadDeviceToken', 'DeviceTokenNotForTopic', 'Unregistered'].includes(reason)) {
          await supabase.from('push_devices').update({ enabled: false, updated_at: new Date().toISOString() }).eq('id', device.id)
        }
        results.push({ device: device.id, status: response.status, reason, sound: alertSound })
      }
    }

    return new Response(JSON.stringify({ ok: true, alert_id: alert.id, sound: alertSound, results }), { headers: jsonHeaders })
  } catch (error: unknown) {
    console.error('vet-ai-apns-push failed', error)
    const message = error instanceof Error ? error.message : String(error)
    return new Response(JSON.stringify({ error: 'push_failed', message }), { status: 500, headers: jsonHeaders })
  }
})
