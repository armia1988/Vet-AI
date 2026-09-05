import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

const shortLanguage = (language: string) => language.trim().toLowerCase().split(/[-_]/)[0] || "en";

const LOCALES: Record<string, string> = {
  ar: "ar-XA", en: "en-GB", nl: "nl-NL", de: "de-DE", fr: "fr-FR", es: "es-ES",
  it: "it-IT", pt: "pt-BR", tr: "tr-TR", ru: "ru-RU", uk: "uk-UA", pl: "pl-PL",
  ro: "ro-RO", el: "el-GR", cs: "cs-CZ", sk: "sk-SK", hu: "hu-HU", bg: "bg-BG",
  hr: "hr-HR", sr: "sr-RS", sl: "sl-SI", sv: "sv-SE", no: "nb-NO", da: "da-DK",
  fi: "fi-FI", he: "he-IL", hi: "hi-IN", bn: "bn-IN", pa: "pa-IN", ta: "ta-IN",
  te: "te-IN", ml: "ml-IN", mr: "mr-IN", gu: "gu-IN", kn: "kn-IN", zh: "cmn-CN",
  ja: "ja-JP", ko: "ko-KR", th: "th-TH", vi: "vi-VN", id: "id-ID", sw: "sw-KE",
};

const CHIRP_SUPPORTED = new Set([
  "ar","en","nl","de","fr","es","it","pt","tr","ru","uk","pl","ro","el","cs","sk",
  "hu","bg","hr","sr","sl","sv","no","da","fi","he","hi","bn","pa","ta","te","ml",
  "mr","gu","kn","zh","ja","ko","th","vi","id","sw"
]);

const sanitize = (input: string) => input
  .replace(/https?:\/\/\S+/gi, " ")
  .replace(/www\.\S+/gi, " ")
  .replace(/[`*_#]+/g, " ")
  .replace(/[•●▪◦‣⁃]+/g, ". ")
  .replace(/(^|\n)\s*[-–—]+\s*/gm, ". ")
  .replace(/(^|\n)\s*\d+[.)]\s*/gm, ". ")
  .replace(/\s+/g, " ")
  .trim()
  .slice(0, 1800);

const base64ToBytes = (value: string) => {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
};

const bytesToBase64 = (bytes: Uint8Array) => {
  let out = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    out += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
  }
  return btoa(out);
};

const writeAscii = (view: DataView, offset: number, value: string) => {
  for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i));
};

const pcmToWav = (pcm: Uint8Array, sampleRate = 24000, channels = 1, bitsPerSample = 16) => {
  const buffer = new ArrayBuffer(44 + pcm.length);
  const view = new DataView(buffer);
  writeAscii(view, 0, "RIFF");
  view.setUint32(4, 36 + pcm.length, true);
  writeAscii(view, 8, "WAVE");
  writeAscii(view, 12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, channels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * channels * bitsPerSample / 8, true);
  view.setUint16(32, channels * bitsPerSample / 8, true);
  view.setUint16(34, bitsPerSample, true);
  writeAscii(view, 36, "data");
  view.setUint32(40, pcm.length, true);
  new Uint8Array(buffer, 44).set(pcm);
  return new Uint8Array(buffer);
};

async function cloudSpeech(text: string, language: string, apiKey: string) {
  const short = shortLanguage(language);
  const languageCode = LOCALES[short] ?? "en-GB";
  const voice = CHIRP_SUPPORTED.has(short)
    ? { languageCode, name: `${languageCode}-Chirp3-HD-Charon`, ssmlGender: "MALE" }
    : { languageCode, ssmlGender: "MALE" };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const response = await fetch(`https://texttospeech.googleapis.com/v1/text:synthesize?key=${encodeURIComponent(apiKey)}`, {
      method: "POST",
      signal: controller.signal,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ input: { text }, voice, audioConfig: { audioEncoding: "MP3" } }),
    });
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      console.warn("case-voice cloud-tts", response.status, String(payload?.error?.message ?? "").slice(0, 320));
      return null;
    }
    const audio = typeof payload?.audioContent === "string" ? payload.audioContent : "";
    if (!audio) return null;
    return { audio, voice: voice.name ?? `${languageCode}-auto`, languageCode };
  } catch (error) {
    console.warn("case-voice cloud-tts exception", error instanceof DOMException && error.name === "AbortError" ? "timeout" : String(error));
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function geminiSpeech(text: string, language: string, key: string) {
  const short = shortLanguage(language);
  const style = short === "ar"
    ? "SYNTHESIZE SPEECH ONLY. Speak as a real Egyptian male veterinarian from Cairo. Use natural Egyptian Arabic pronunciation, rhythm and pauses. Warm, calm, professional and conversational. Read the transcript exactly without adding, removing or paraphrasing anything. Do not read these instructions aloud."
    : `SYNTHESIZE SPEECH ONLY. Read the transcript exactly in language ${language}. Use a natural, warm, professional male veterinary-clinician delivery with realistic human pauses and conversational intonation. Do not read these instructions aloud.`;
  const prompt = `${style}\n\nVERBATIM TRANSCRIPT START\n${text}\nVERBATIM TRANSCRIPT END`;
  const models = ["gemini-3.1-flash-tts-preview", "gemini-2.5-flash-preview-tts"];

  for (const model of models) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 12000);
    try {
      const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
        method: "POST",
        signal: controller.signal,
        headers: { "x-goog-api-key": key, "content-type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          generationConfig: {
            responseModalities: ["AUDIO"],
            speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: "Charon" } } },
          },
        }),
      });
      const payload = await response.json().catch(() => null);
      if (!response.ok) {
        console.warn("case-voice gemini-tts", model, response.status, String(payload?.error?.message ?? "").slice(0, 320));
        continue;
      }
      const part = payload?.candidates?.[0]?.content?.parts?.find((p: any) => p?.inlineData?.data || p?.inline_data?.data);
      const raw = part?.inlineData?.data ?? part?.inline_data?.data;
      if (typeof raw !== "string" || !raw) continue;
      const pcm = base64ToBytes(raw);
      if (!pcm.length || pcm.length > 8 * 1024 * 1024) continue;
      return { audio: bytesToBase64(pcmToWav(pcm)), model };
    } catch (error) {
      console.warn("case-voice gemini-tts exception", model, error instanceof DOMException && error.name === "AbortError" ? "timeout" : String(error));
    } finally {
      clearTimeout(timer);
    }
  }
  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
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
  const text = sanitize(typeof body?.text === "string" ? body.text : "");
  const language = typeof body?.language === "string" && body.language.trim() ? body.language.trim().toLowerCase() : "en";
  if (!text) return json({ error: "Text is required" }, 400);

  const googleKey = Deno.env.get("GOOGLE_API_KEY")?.trim() ?? "";
  const geminiKey = Deno.env.get("GEMINI_API_KEY")?.trim() ?? "";

  const cloudKeys = [...new Set([googleKey, geminiKey].filter(Boolean))];
  for (const key of cloudKeys) {
    const cloud = await cloudSpeech(text, language, key);
    if (cloud) {
      return json({
        audio_base64: cloud.audio,
        mime_type: "audio/mpeg",
        provider: "google-cloud-tts",
        voice: cloud.voice,
        language_code: cloud.languageCode,
        requested_language: language,
      });
    }
  }

  if (geminiKey) {
    const gemini = await geminiSpeech(text, language, geminiKey);
    if (gemini) {
      return json({
        audio_base64: gemini.audio,
        mime_type: "audio/wav",
        provider: "gemini-tts",
        voice: "Charon",
        model: gemini.model,
        requested_language: language,
      });
    }
  }

  return json({
    code: "VOICE_TEMPORARILY_UNAVAILABLE",
    google_api_key_configured: Boolean(googleKey),
    gemini_key_configured: Boolean(geminiKey),
  }, 503);
});