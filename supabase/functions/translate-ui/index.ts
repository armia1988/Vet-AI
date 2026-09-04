import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = Deno.env.get("VET_AI_GEMINI_TRANSLATION_MODEL") ?? "gemini-2.5-flash-lite";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8" } });
const supported = new Set(['de','fr','es','it','pt','tr','ru','uk','pl','ro','el','cs','sk','hu','bg','hr','sr','sl','sv','no','da','fi','he','fa','ur','hi','bn','pa','ta','te','ml','mr','gu','kn','zh','ja','ko','th','vi','id','ms','fil','sw','am','zu']);
const publicCore = new Set([
  'Language','Automatic','Device language','Preparing language…','Home','AI Scan','Sensors','Alerts','History','Account & settings','Real data policy','No demo sensor readings and no definitive diagnosis from one image.','Health monitoring overview','Barns','Workers','Veterinarians','Plan','Smart monitoring','Software only','AI health scan','Image + symptoms + reviewed veterinary knowledge. Not a definitive diagnosis.','Livestock','Poultry','Dogs','Camera','Photos','Symptoms / history / recent changes','Analyze case','Analyzing safely…','Fast preliminary assessment','Final verified report','Most likely at this stage','Disease / most likely condition','Cause','Treatment / management','Treatment & management','Prevention','What to do now','What you should do now','Veterinary next steps','Danger signs','How to confirm','Trusted sources used','Answer these to improve the report','Yes','No','Unknown','Send answers & create final report','Create final verified report','Checking trusted sources…','Mute result','Turn sound on','Create account','Sign in','Full name','Phone','Email','Password','Confirm your email','Profile & farm data','Subscription','Support chat','About Vet AI'
]);
const geminiText = (payload: any): string | null => {
  for (const candidate of payload?.candidates ?? []) {
    for (const part of candidate?.content?.parts ?? []) {
      if (typeof part?.text === 'string' && part.text.trim()) return part.text.trim();
    }
  }
  return null;
};

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const body = await req.json().catch(() => ({}));
  const target = typeof body?.target_language === 'string' ? body.target_language.toLowerCase() : '';
  if (!supported.has(target)) return json({ error: 'Unsupported language' }, 422);

  const single = typeof body?.text === 'string' ? body.text.trim() : '';
  const incoming = Array.isArray(body?.texts) ? body.texts : single ? [single] : [];
  const texts = incoming.filter((x: unknown) => typeof x === 'string').map((x: string) => x.trim()).filter((x: string) => x.length > 0 && x.length <= 1600).slice(0, 80);
  if (!texts.length) return json({ error: 'No valid text' }, 400);
  const totalChars = texts.reduce((n: number, x: string) => n + x.length, 0);
  if (totalChars > 24000) return json({ error: 'Translation batch too large' }, 413);

  let authenticated = false;
  const auth = req.headers.get('Authorization');
  if (auth?.startsWith('Bearer ')) {
    const token = auth.slice(7).trim();
    if (token.split('.').length === 3) {
      try {
        const publishable = JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') ?? '{}')['default'];
        if (publishable) {
          const client = createClient(Deno.env.get('SUPABASE_URL')!, publishable, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
          const { data } = await client.auth.getUser();
          authenticated = Boolean(data.user);
        }
      } catch (_) {}
    }
  }
  if (!authenticated && texts.some((x: string) => !publicCore.has(x))) return json({ error: 'Authentication required for non-core UI translation' }, 401);

  const key = Deno.env.get('GEMINI_API_KEY');
  if (!key) return json({ code: 'GEMINI_NOT_CONFIGURED', message: 'Gemini translation is not configured.' }, 503);

  const schema = {
    type: 'OBJECT',
    properties: {
      translations: { type: 'ARRAY', items: { type: 'STRING' }, minItems: texts.length, maxItems: texts.length },
    },
    required: ['translations'],
  };

  const response = await fetch(`${BASE}/${encodeURIComponent(MODEL)}:generateContent`, {
    method: 'POST',
    headers: { 'x-goog-api-key': key, 'content-type': 'application/json' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: 'Translate Vet AI mobile application UI text accurately and naturally. Preserve Vet AI, AI, numbers, units, placeholders, URLs, medical abbreviations and symbols. Do not add or remove medical claims. Translate each input independently and preserve its meaning. Return translations in exactly the same order.' }] },
      contents: [{ role: 'user', parts: [{ text: `Target language code: ${target}\nInput strings JSON: ${JSON.stringify(texts)}` }] }],
      generationConfig: {
        temperature: 0.1,
        maxOutputTokens: Math.min(8192, 500 + totalChars * 2),
        responseMimeType: 'application/json',
        responseSchema: schema,
      },
    }),
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok || !payload) {
    const statusName = String(payload?.error?.status ?? '');
    console.error('translate-ui Gemini error', response.status, statusName, payload?.error?.message ?? '');
    if (response.status === 429 || statusName === 'RESOURCE_EXHAUSTED') return json({ code: 'GEMINI_RATE_LIMIT' }, 429);
    if (response.status === 401 || response.status === 403 || statusName === 'PERMISSION_DENIED' || statusName === 'UNAUTHENTICATED') return json({ code: 'GEMINI_AUTH_ERROR' }, 502);
    return json({ code: 'GEMINI_TRANSLATION_ERROR' }, 502);
  }

  const raw = geminiText(payload);
  if (!raw) return json({ code: 'EMPTY_TRANSLATION' }, 502);
  let parsed: any;
  try { parsed = JSON.parse(raw); } catch { return json({ code: 'INVALID_TRANSLATION' }, 502); }
  const translations = Array.isArray(parsed?.translations) ? parsed.translations.map((x: unknown) => String(x ?? '').trim()) : [];
  if (translations.length !== texts.length || translations.some((x: string) => !x)) return json({ code: 'INVALID_TRANSLATION_COUNT' }, 502);
  return json({ translations, target_language: target, provider: 'gemini', model: MODEL });
});