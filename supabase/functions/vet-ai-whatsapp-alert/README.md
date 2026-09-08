# Vet AI WhatsApp Alert Setup

This Edge Function sends Vet AI orange/red alerts through the official Meta WhatsApp Cloud API.

## Required Supabase Edge Function secrets

- `WHATSAPP_GRAPH_VERSION` — Graph API version shown by Meta for the app, for example `vXX.X`.
- `WHATSAPP_ACCESS_TOKEN` — long-lived/system-user access token with WhatsApp messaging permission.
- `WHATSAPP_PHONE_NUMBER_ID` — Meta Phone Number ID used by the `/messages` endpoint.
- `WHATSAPP_TEMPLATE_NAME` — approved WhatsApp message template name.
- `WHATSAPP_TEMPLATE_LANGUAGE` — fallback approved template language code.
- Optional per-language overrides: `WHATSAPP_TEMPLATE_LANGUAGE_AR`, `WHATSAPP_TEMPLATE_LANGUAGE_EN`, `WHATSAPP_TEMPLATE_LANGUAGE_NL`.
- `WHATSAPP_INTERNAL_DISPATCH_SECRET` — private shared secret used only between the database alert trigger and this Edge Function. Never commit its real value.

The production database trigger must send the same internal secret in the `X-Vet-AI-Internal` header.

## Template body variables

The approved template body must contain seven text variables in this exact order:

1. `{{1}}` Farm name
2. `{{2}}` Risk (`ORANGE` or `RED`)
3. `{{3}}` Sensor/metric
4. `{{4}}` Measured reading
5. `{{5}}` Configured threshold
6. `{{6}}` Alert details
7. `{{7}}` Event time

Suggested English template body:

```text
🚨 Vet AI alert
Farm: {{1}}
Severity: {{2}}
Sensor / metric: {{3}}
Reading: {{4}}
Threshold: {{5}}
Details: {{6}}
Time: {{7}}
Open Vet AI to review the alert. If the animal may be in immediate danger, contact a veterinarian.
```

Suggested Arabic translation:

```text
🚨 تنبيه Vet AI
المزرعة: {{1}}
درجة الخطورة: {{2}}
الحساس / المؤشر: {{3}}
القراءة: {{4}}
الحد المضبوط: {{5}}
التفاصيل: {{6}}
الوقت: {{7}}
افتح Vet AI لمراجعة التنبيه. إذا كان الحيوان في خطر فوري، تواصل مع طبيب بيطري.
```

## Phone format

Recipients must be stored in E.164 format, such as `+316...` or `+201...`. The function refuses ambiguous local-format numbers.

## Safety defaults

- WhatsApp preferences are created disabled.
- Only `orange` and `red` alerts are eligible.
- A per-recipient minimum risk can be `orange` or `red`.
- Delivery is idempotent per `(alert_id, recipient_user_id)` to prevent duplicate sends.
