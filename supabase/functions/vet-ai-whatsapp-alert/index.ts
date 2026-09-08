import { createClient } from 'npm:@supabase/supabase-js@2'

const jsonHeaders = { 'Content-Type': 'application/json' }

function env(name: string): string {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new Error(`Missing ${name}`)
  return value
}

function optionalEnv(name: string): string | null {
  const value = Deno.env.get(name)?.trim()
  return value ? value : null
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

function cleanText(value: unknown, max = 500): string {
  const text = String(value ?? '')
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  if (!text) return '—'
  return text.length <= max ? text : `${text.slice(0, max - 1)}…`
}

function normalizeWhatsAppPhone(value: unknown): string | null {
  let raw = String(value ?? '').trim()
  if (!raw) return null
  raw = raw.replace(/[()\-\.\s]/g, '')
  if (raw.startsWith('00')) raw = `+${raw.slice(2)}`
  if (!/^\+[1-9][0-9]{7,14}$/.test(raw)) return null
  return raw.slice(1)
}

function preferredTemplateLanguage(language: unknown): string | null {
  const code = String(language ?? 'en').trim().toLowerCase().split(/[-_]/)[0]
  const perLanguage = optionalEnv(`WHATSAPP_TEMPLATE_LANGUAGE_${code.toUpperCase()}`)
  return perLanguage ?? optionalEnv('WHATSAPP_TEMPLATE_LANGUAGE')
}

function riskAllowsAlert(minimumRisk: unknown, risk: unknown): boolean {
  const minimum = String(minimumRisk ?? 'orange').toLowerCase()
  const actual = String(risk ?? '').toLowerCase()
  if (actual !== 'orange' && actual !== 'red') return false
  if (minimum === 'red') return actual === 'red'
  return true
}

async function updateDelivery(
  supabase: any,
  alert: any,
  recipientUserId: string,
  values: Record<string, unknown>,
) {
  const payload = {
    alert_id: alert.id,
    farm_id: alert.farm_id,
    recipient_user_id: recipientUserId,
    provider: 'meta_cloud_api',
    updated_at: new Date().toISOString(),
    ...values,
  }
  return await supabase
    .from('whatsapp_deliveries')
    .upsert(payload, { onConflict: 'alert_id,recipient_user_id' })
    .select('id,status')
    .maybeSingle()
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
    const alertId = String(body?.alert_id ?? '').trim()
    if (!/^[0-9a-f-]{36}$/i.test(alertId)) {
      return new Response(JSON.stringify({ error: 'invalid_alert_id' }), {
        status: 400,
        headers: jsonHeaders,
      })
    }

    const supabase = createClient(env('SUPABASE_URL'), adminKey(), {
      auth: { persistSession: false, autoRefreshToken: false },
    })

    const { data: alert, error: alertError } = await supabase
      .from('alerts')
      .select('id,farm_id,animal_id,risk,title,details,source,metric,value_numeric,threshold_text,created_at')
      .eq('id', alertId)
      .maybeSingle()

    if (alertError) throw alertError
    if (!alert) {
      return new Response(JSON.stringify({ ok: true, skipped: 'alert_not_found' }), {
        headers: jsonHeaders,
      })
    }

    if (!['orange', 'red'].includes(String(alert.risk).toLowerCase())) {
      return new Response(JSON.stringify({ ok: true, skipped: 'risk_not_whatsapp_eligible' }), {
        headers: jsonHeaders,
      })
    }

    const { data: preferences, error: prefError } = await supabase
      .from('whatsapp_alert_preferences')
      .select('id,recipient_user_id,enabled,minimum_risk,phone_e164,language')
      .eq('farm_id', alert.farm_id)
      .eq('enabled', true)

    if (prefError) throw prefError
    if (!preferences?.length) {
      return new Response(JSON.stringify({ ok: true, sent: 0, reason: 'whatsapp_disabled' }), {
        headers: jsonHeaders,
      })
    }

    const graphVersion = optionalEnv('WHATSAPP_GRAPH_VERSION')
    const accessToken = optionalEnv('WHATSAPP_ACCESS_TOKEN')
    const phoneNumberId = optionalEnv('WHATSAPP_PHONE_NUMBER_ID')
    const templateName = optionalEnv('WHATSAPP_TEMPLATE_NAME')

    if (!graphVersion || !accessToken || !phoneNumberId || !templateName) {
      return new Response(
        JSON.stringify({
          ok: true,
          sent: 0,
          reason: 'provider_not_configured',
          missing: [
            !graphVersion ? 'WHATSAPP_GRAPH_VERSION' : null,
            !accessToken ? 'WHATSAPP_ACCESS_TOKEN' : null,
            !phoneNumberId ? 'WHATSAPP_PHONE_NUMBER_ID' : null,
            !templateName ? 'WHATSAPP_TEMPLATE_NAME' : null,
          ].filter(Boolean),
        }),
        { headers: jsonHeaders },
      )
    }

    const { data: farm, error: farmError } = await supabase
      .from('farms')
      .select('farm_name')
      .eq('id', alert.farm_id)
      .maybeSingle()
    if (farmError) throw farmError

    const results: Array<Record<string, unknown>> = []

    for (const pref of preferences) {
      if (!riskAllowsAlert(pref.minimum_risk, alert.risk)) {
        results.push({ recipient_user_id: pref.recipient_user_id, skipped: 'below_preference_threshold' })
        continue
      }

      const { data: profile, error: profileError } = await supabase
        .from('profiles')
        .select('phone,preferred_language')
        .eq('id', pref.recipient_user_id)
        .maybeSingle()
      if (profileError) throw profileError
      if (!profile) {
        results.push({ recipient_user_id: pref.recipient_user_id, skipped: 'profile_not_found' })
        continue
      }

      const phone = normalizeWhatsAppPhone(pref.phone_e164 || profile.phone)
      const language = preferredTemplateLanguage(pref.language || profile.preferred_language)

      if (!phone) {
        await updateDelivery(supabase, alert, pref.recipient_user_id, {
          status: 'failed',
          template_name: templateName,
          error: 'invalid_phone_e164',
        })
        results.push({ recipient_user_id: pref.recipient_user_id, failed: 'invalid_phone_e164' })
        continue
      }

      if (!language) {
        await updateDelivery(supabase, alert, pref.recipient_user_id, {
          status: 'failed',
          template_name: templateName,
          error: 'template_language_not_configured',
        })
        results.push({ recipient_user_id: pref.recipient_user_id, failed: 'template_language_not_configured' })
        continue
      }

      const { data: existing } = await supabase
        .from('whatsapp_deliveries')
        .select('id,status,provider_message_id')
        .eq('alert_id', alert.id)
        .eq('recipient_user_id', pref.recipient_user_id)
        .maybeSingle()

      if (existing?.status === 'sent') {
        results.push({ recipient_user_id: pref.recipient_user_id, skipped: 'already_sent' })
        continue
      }

      const sending = await updateDelivery(supabase, alert, pref.recipient_user_id, {
        status: 'sending',
        template_name: templateName,
        error: null,
      })
      if (sending.error) throw sending.error

      const riskLabel = String(alert.risk).toUpperCase()
      const reading = alert.value_numeric == null ? '—' : String(alert.value_numeric)
      const metric = cleanText(alert.metric || alert.source || 'health alert', 120)
      const threshold = cleanText(alert.threshold_text, 160)
      const details = cleanText(alert.details || alert.title, 480)
      const createdAt = alert.created_at
        ? `${new Date(alert.created_at).toISOString().replace('T', ' ').replace('.000Z', 'Z')}`
        : new Date().toISOString()

      // Approved template body must contain seven text variables in this order:
      // {{1}} farm, {{2}} risk, {{3}} metric, {{4}} reading,
      // {{5}} threshold, {{6}} details, {{7}} event time.
      const payload = {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: phone,
        type: 'template',
        template: {
          name: templateName,
          language: { code: language },
          components: [
            {
              type: 'body',
              parameters: [
                { type: 'text', text: cleanText(farm?.farm_name || 'Vet AI farm', 120) },
                { type: 'text', text: riskLabel },
                { type: 'text', text: metric },
                { type: 'text', text: reading },
                { type: 'text', text: threshold },
                { type: 'text', text: details },
                { type: 'text', text: createdAt },
              ],
            },
          ],
        },
      }

      const response = await fetch(
        `https://graph.facebook.com/${encodeURIComponent(graphVersion)}/${encodeURIComponent(phoneNumberId)}/messages`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
        },
      )

      const responseBody: any = await response.json().catch(() => ({}))
      const providerMessageId = String(responseBody?.messages?.[0]?.id ?? '').trim() || null

      if (response.ok && providerMessageId) {
        await updateDelivery(supabase, alert, pref.recipient_user_id, {
          status: 'sent',
          provider_message_id: providerMessageId,
          template_name: templateName,
          error: null,
          sent_at: new Date().toISOString(),
        })
        results.push({ recipient_user_id: pref.recipient_user_id, status: 'sent' })
      } else {
        const providerError = cleanText(
          responseBody?.error?.message || responseBody?.error?.error_user_msg || `HTTP_${response.status}`,
          500,
        )
        await updateDelivery(supabase, alert, pref.recipient_user_id, {
          status: 'failed',
          template_name: templateName,
          error: providerError,
        })
        results.push({ recipient_user_id: pref.recipient_user_id, status: 'failed', error: providerError })
      }
    }

    return new Response(JSON.stringify({ ok: true, alert_id: alert.id, results }), {
      headers: jsonHeaders,
    })
  } catch (error) {
    console.error('vet-ai-whatsapp-alert failed', error)
    return new Response(
      JSON.stringify({ error: 'whatsapp_alert_failed', message: String(error?.message ?? error) }),
      { status: 500, headers: jsonHeaders },
    )
  }
})
