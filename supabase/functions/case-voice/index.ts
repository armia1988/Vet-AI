import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = Deno.env.get("VET_AI_GEMINI_TTS_MODEL") ?? "gemini-3.1-flash-tts-preview";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8" } });

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

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Missing authorization" }, 401);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

  const body = await req.json().catch(() => ({}));
  const text = typeof body?.text === "string" ? body.text.trim().slice(0, 4000) : "";
  const language = typeof body?.language === "string" ? body.language.toLowerCase() : "en";
  if (!text) return json({ error: "Text is required" }, 400);

  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key) return json({ code: "GEMINI_TTS_NOT_CONFIGURED" }, 503);

  const style = language.startsWith("ar")
    ? "Read the following text exactly in natural Egyptian Arabic. Use a warm, calm, professional feminine veterinary-clinician voice. Sound natural and confident, not robotic. Do not add, remove or paraphrase anything. Pronounce Vet AI naturally."
    : `Read the following text exactly in language code ${language}. Use a warm, calm, professional feminine veterinary-clinician voice. Sound natural and measured. Do not add, remove or paraphrase anything.`;
  const prompt = `${style}\n\nTEXT TO READ:\n${text}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(MODEL)}:generateContent`, {
      method: "POST",
      signal: controller.signal,
      headers: { "x-goog-api-key": key, "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          responseModalities: ["AUDIO"],
          speechConfig: {
            voiceConfig: { prebuiltVoiceConfig: { voiceName: "Kore" } },
          },
        },
      }),
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok || !payload) {
      const statusName = String(payload?.error?.status ?? "");
      console.error("case-voice Gemini error", response.status, statusName, payload?.error?.message ?? "");
      if (response.status === 429 || statusName === "RESOURCE_EXHAUSTED") return json({ code: "GEMINI_TTS_RATE_LIMIT" }, 429);
      if (response.status === 401 || response.status === 403 || statusName === "PERMISSION_DENIED" || statusName === "UNAUTHENTICATED") return json({ code: "GEMINI_TTS_AUTH_ERROR" }, 502);
      return json({ code: "GEMINI_TTS_ERROR" }, 502);
    }

    const part = payload?.candidates?.[0]?.content?.parts?.find((p: any) => p?.inlineData?.data || p?.inline_data?.data);
    const rawBase64 = part?.inlineData?.data ?? part?.inline_data?.data;
    if (typeof rawBase64 !== "string" || !rawBase64) return json({ code: "GEMINI_TTS_EMPTY" }, 502);

    const pcm = base64ToBytes(rawBase64);
    if (!pcm.length || pcm.length > 8 * 1024 * 1024) return json({ code: "GEMINI_TTS_OUTPUT_INVALID" }, 502);
    const wav = pcmToWav(pcm, 24000, 1, 16);
    return json({
      audio_base64: bytesToBase64(wav),
      mime_type: "audio/wav",
      voice: "Kore",
      provider: "gemini",
      model: MODEL,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") return json({ code: "GEMINI_TTS_TIMEOUT" }, 504);
    console.error("case-voice Gemini unhandled", error);
    return json({ code: "GEMINI_TTS_ERROR" }, 502);
  } finally {
    clearTimeout(timer);
  }
});