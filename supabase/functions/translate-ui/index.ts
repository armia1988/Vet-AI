import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8" },
});

const supported = new Set([
  'de','fr','es','it','pt','tr','ru','uk','pl','ro','el','cs','sk','hu','bg','hr','sr','sl','sv','no','da','fi',
  'he','fa','ur','hi','bn','pa','ta','te','ml','mr','gu','kn','zh','ja','ko','th','vi','id','ms','fil','sw','am','zu'
]);

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const auth = req.headers.get('Authorization');
  if (!auth) return json({ error: 'Missing authorization' }, 401);

  const body = await req.json().catch(() => ({}));
  const text = typeof body?.text === 'string' ? body.text.trim() : '';
  const target = typeof body?.target_language === 'string' ? body.target_language.toLowerCase() : '';
  if (!text || text.length > 1200) return json({ error: 'Invalid text' }, 400);
  if (!supported.has(target)) return json({ error: 'Unsupported language' }, 422);

  const providerKey = Deno.env.get('VET_AI_PROVIDER_KEY') ?? Deno.env.get('OPENAI_API_KEY');
  if (!providerKey) return json({ code: 'AI_PROVIDER_NOT_CONFIGURED', message: 'Translation provider is not configured.' }, 503);

  const response = await fetch('https://api.openai.com/v1/responses', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${providerKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-5.6-luna',
      store: false,
      reasoning: { effort: 'none' },
      max_output_tokens: 400,
      input: [
        {
          role: 'developer',
          content: [{
            type: 'input_text',
            text: 'Translate mobile application UI text accurately and naturally. Preserve Vet AI, AI, numbers, units, placeholders, punctuation, URLs, product names, medical abbreviations and symbols. Return only the translated text, no quotation marks or commentary. Do not add medical claims.'
          }]
        },
        {
          role: 'user',
          content: [{ type: 'input_text', text: `Target language code: ${target}\nText: ${text}` }]
        }
      ]
    }),
  });

  const payload = await response.json().catch(() => null);
  if (!response.ok || !payload) return json({ code: 'TRANSLATION_PROVIDER_ERROR' }, 502);

  let translated: string | null = typeof payload.output_text === 'string' ? payload.output_text : null;
  if (!translated) {
    for (const item of payload.output ?? []) {
      if (item?.type !== 'message') continue;
      for (const part of item?.content ?? []) {
        if (part?.type === 'output_text' && typeof part.text === 'string') translated = part.text;
      }
    }
  }
  if (!translated?.trim()) return json({ code: 'EMPTY_TRANSLATION' }, 502);
  return json({ translation: translated.trim(), target_language: target });
});
