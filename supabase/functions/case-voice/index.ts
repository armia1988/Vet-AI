import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_TTS_MODEL") ?? "gemini-2.5-flash-preview-tts";
const FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_TTS_FALLBACK_MODEL") ?? "gemini-3.1-flash-tts-preview";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

const base64ToBytes = (value: string) => {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
};
const bytesToBase64 = (bytes: Uint8Array) => {
  let out = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    out += String.fromCharCode(...bytes.subarray(i, Math.min(i + chunk, bytes.length)));
  }
  return btoa(out);
};
const writeAscii = (view: DataView, offset: number, value: string) => {
  for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i));
};
const pcmToWav = (pcm: Uint8Array, sampleRate = 24000, channels = 1, bitsPerSample = 16) => {
  const header = 44;
  const buffer = new ArrayBuffer(header + pcm.length);
  const view = new DataView(buffer);
  writeAscii(view, 0, "RIFF");
  view.setUint32(4, 36 + pcm.length, true);
  writeAscii(view, 8, "WAVE");
  writeAscii(view, 12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  const byteRate = sampleRate * channels * bitsPerSample / 8;
  view.setUint32(28, byteRate, true);
  view.setUint16(32, channels * bitsPerSample / 8, true);
  view.setUint16(34, bitsPerSample, true);
  writeAscii(view, 36, "data");
  view.setUint32(40, pcm.length, true);
  new Uint8Array(buffer, header).set(pcm);
  return new Uint8Array(buffer);
};
const languageCode = (language: string) => {
  if (language.startsWith("ar")) return "ar-XA";
  if (language.startsWith("nl")) return "nl-NL";
  if (language.startsWith("de")) return "de-DE";
  if (language.startsWith("fr")) return "fr-FR";
  if (language.startsWith("es")) return "es-ES";
  if (language.startsWith("it")) return "it-IT";
  if (language.startsWith("tr")) return "tr-TR";
  if (language.startsWith("pt")) return "pt-BR";
  if (language.startsWith("ja")) return "ja-JP";
  if (language.startsWith("ko")) return "ko-KR";
  if (language.startsWith("ru")) return "ru-RU";
  return "en-US";
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Missing authorization" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

  const body = await req.json().catch(() => ({}));
  const rawText = typeof body?.text === "string" ? body.text.trim() : "";
  const text = rawText.slice(0, 1800);
  const language = typeof body?.language === "string" ? body.language.toLowerCase() : "en";
  if (!text) return json({ error: "Text is required" }, 400);

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) return json({ code: "GEMINI_TTS_NOT_CONFIGURED" }, 503);

  const isArabic = language.startsWith("ar");
  const style = isArabic
    ? "SYNTHESIZE SPEECH ONLY. Speak as a real Egyptian female veterinarian from Cairo. Use natural Egyptian Arabic pronunciation and rhythm, warm and reassuring but professional, with human pauses and normal conversational intonation. Avoid a formal newsreader or robotic delivery. Read the transcript exactly without adding, removing or paraphrasing words. Do not read these instructions aloud."
    : `SYNTHESIZE SPEECH ONLY. Read the transcript exactly in language code ${language}, using a warm, natural, professional female veterinary-clinician delivery with realistic pauses and conversational intonation. Do not read these instructions aloud.`;
  const prompt = `${style}\n\nVERBATIM TRANSCRIPT START\n${text}\nVERBATIM TRANSCRIPT END`;

  const callModel = async (model: string, timeoutMs: number) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
        method: "POST",
        signal: controller.signal,
        headers: { "x-goog-api-key": key, "content-type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: {
            responseModalities: ["AUDIO"],
            speechConfig: {
              languageCode: languageCode(language),
              voiceConfig: { prebuiltVoiceConfig: { voiceName: "Sulafat" } },
            },
          },
        }),
      });
      const payload = await response.json().catch(() => null);
      return { response, payload };
    } finally {
      clearTimeout(timer);
    }
  };

  const attempts = [
    { model: PRIMARY_MODEL, timeoutMs: 18000 },
    { model: FALLBACK_MODEL, timeoutMs: 18000 },
  ].filter((a, index, rows) => rows.findIndex((x) => x.model === a.model) === index);

  for (const attempt of attempts) {
    try {
      const { response, payload } = await callModel(attempt.model, attempt.timeoutMs);
      if (!response.ok || !payload) {
        console.warn("case-voice provider attempt failed", attempt.model, response.status, payload?.error?.status ?? "", String(payload?.error?.message ?? "").slice(0, 350));
        continue;
      }
      const part = payload?.candidates?.[0]?.content?.parts?.find((p: any) => p?.inlineData?.data || p?.inline_data?.data);
      const rawBase64 = part?.inlineData?.data ?? part?.inline_data?.data;
      if (typeof rawBase64 !== "string" || !rawBase64) {
        console.warn("case-voice empty audio", attempt.model, payload?.candidates?.[0]?.finishReason ?? "");
        continue;
      }
      const pcm = base64ToBytes(rawBase64);
      if (!pcm.length || pcm.length > 8 * 1024 * 1024) continue;
      const wav = pcmToWav(pcm, 24000, 1, 16);
      return json({
        audio_base64: bytesToBase64(wav),
        mime_type: "audio/wav",
        voice: "Sulafat",
        provider: "gemini",
        model: attempt.model,
        egyptian_arabic_style: isArabic,
      });
    } catch (error) {
      const timeout = error instanceof DOMException && error.name === "AbortError";
      console.warn("case-voice attempt exception", attempt.model, timeout ? "timeout" : String(error));
    }
  }

  return json({ code: "GEMINI_TTS_TEMPORARILY_UNAVAILABLE" }, 503);
});
