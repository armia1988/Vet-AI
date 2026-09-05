import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const PRIMARY_GEMINI_MODEL = Deno.env.get("VET_AI_GEMINI_TTS_MODEL") ?? "gemini-3.1-flash-tts-preview";
const FALLBACK_GEMINI_MODEL = Deno.env.get("VET_AI_GEMINI_TTS_FALLBACK_MODEL") ?? "gemini-2.5-flash-preview-tts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: {
    ...corsHeaders,
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  },
});

type GoogleVoice = {
  languageCode: string;
  name?: string;
  ssmlGender?: "MALE" | "FEMALE" | "NEUTRAL";
};

const GOOGLE_LOCALES: Record<string, string> = {
  en: "en-GB", ar: "ar-XA", nl: "nl-NL", de: "de-DE", fr: "fr-FR",
  es: "es-ES", it: "it-IT", pt: "pt-PT", tr: "tr-TR", ru: "ru-RU",
  uk: "uk-UA", pl: "pl-PL", ro: "ro-RO", el: "el-GR", cs: "cs-CZ",
  sk: "sk-SK", hu: "hu-HU", bg: "bg-BG", hr: "hr-HR", sr: "sr-RS",
  sl: "sl-SI", sv: "sv-SE", no: "nb-NO", da: "da-DK", fi: "fi-FI",
  he: "he-IL", fa: "fa-IR", ur: "ur-PK", hi: "hi-IN", bn: "bn-IN",
  pa: "pa-IN", ta: "ta-IN", te: "te-IN", ml: "ml-IN", mr: "mr-IN",
  gu: "gu-IN", kn: "kn-IN", zh: "cmn-CN", ja: "ja-JP", ko: "ko-KR",
  th: "th-TH", vi: "vi-VN", id: "id-ID", ms: "ms-MY", fil: "fil-PH",
  sw: "sw-KE", am: "am-ET", zu: "zu-ZA",
};

const PINNED_GOOGLE_VOICES: Record<string, GoogleVoice> = {
  ar: { languageCode: "ar-XA", name: "ar-XA-Wavenet-B", ssmlGender: "MALE" },
  en: { languageCode: "en-GB", name: "en-GB-Wavenet-B", ssmlGender: "MALE" },
  nl: { languageCode: "nl-NL", name: "nl-NL-Wavenet-G", ssmlGender: "MALE" },
  de: { languageCode: "de-DE", name: "de-DE-Wavenet-H", ssmlGender: "MALE" },
  fr: { languageCode: "fr-FR", name: "fr-FR-Wavenet-G", ssmlGender: "MALE" },
  es: { languageCode: "es-ES", name: "es-ES-Wavenet-G", ssmlGender: "MALE" },
  it: { languageCode: "it-IT", name: "it-IT-Wavenet-F", ssmlGender: "MALE" },
  pt: { languageCode: "pt-PT", name: "pt-PT-Wavenet-F", ssmlGender: "MALE" },
  tr: { languageCode: "tr-TR", name: "tr-TR-Wavenet-B", ssmlGender: "MALE" },
  ru: { languageCode: "ru-RU", name: "ru-RU-Wavenet-B", ssmlGender: "MALE" },
  hi: { languageCode: "hi-IN", name: "hi-IN-Wavenet-B", ssmlGender: "MALE" },
  zh: { languageCode: "cmn-CN", name: "cmn-CN-Wavenet-B", ssmlGender: "MALE" },
  ja: { languageCode: "ja-JP", name: "ja-JP-Wavenet-C", ssmlGender: "MALE" },
  ko: { languageCode: "ko-KR", name: "ko-KR-Wavenet-C", ssmlGender: "MALE" },
};

const shortLanguage = (language: string) => language.trim().toLowerCase().split(/[-_]/)[0] || "en";
const googleVoiceFor = (language: string): GoogleVoice => {
  const short = shortLanguage(language);
  return PINNED_GOOGLE_VOICES[short] ?? {
    languageCode: GOOGLE_LOCALES[short] ?? "en-GB",
    ssmlGender: "MALE",
  };
};

const sanitizeSpeechText = (input: string) => input
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
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) out += String.fromCharCode(...bytes.subarray(i, Math.min(i + chunk, bytes.length)));
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
const b64Url = (bytes: Uint8Array) => {
  let raw = "";
  for (let i = 0; i < bytes.length; i += 0x8000) raw += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
  return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
};
const utf8B64Url = (value: string) => b64Url(new TextEncoder().encode(value));

async function serviceAccountAccessToken(): Promise<{ token: string; projectId: string } | null> {
  const raw = Deno.env.get("GOOGLE_CLOUD_TTS_SERVICE_ACCOUNT_JSON");
  if (!raw) return null;
  try {
    const sa = JSON.parse(raw);
    const clientEmail = String(sa?.client_email ?? "");
    const privateKeyPem = String(sa?.private_key ?? "");
    const projectId = String(sa?.project_id ?? "");
    if (!clientEmail || !privateKeyPem) return null;
    const pemBody = privateKeyPem.replace(/-----BEGIN PRIVATE KEY-----/g, "").replace(/-----END PRIVATE KEY-----/g, "").replace(/\s+/g, "");
    const pemBinary = atob(pemBody);
    const pemBytes = new Uint8Array(pemBinary.length);
    for (let i = 0; i < pemBinary.length; i++) pemBytes[i] = pemBinary.charCodeAt(i);
    const signingKey = await crypto.subtle.importKey("pkcs8", pemBytes.buffer, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
    const now = Math.floor(Date.now() / 1000);
    const header = utf8B64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
    const payload = utf8B64Url(JSON.stringify({ iss: clientEmail, scope: "https://www.googleapis.com/auth/cloud-platform", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3300 }));
    const unsigned = `${header}.${payload}`;
    const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", signingKey, new TextEncoder().encode(unsigned));
    const assertion = `${unsigned}.${b64Url(new Uint8Array(signature))}`;
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
    });
    const tokenPayload = await tokenResponse.json().catch(() => null);
    const token = typeof tokenPayload?.access_token === "string" ? tokenPayload.access_token : "";
    if (!tokenResponse.ok || !token) {
      console.warn("case-voice service-account token exchange failed", tokenResponse.status);
      return null;
    }
    return { token, projectId };
  } catch (error) {
    console.warn("case-voice service-account auth exception", String(error));
    return null;
  }
}

async function requestGoogleCloudTts(text: string, language: string, auth: { apiKey?: string; accessToken?: string; projectId?: string }) {
  const preferred = googleVoiceFor(language);
  const call = async (voice: GoogleVoice) => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 9000);
    try {
      const endpoint = auth.apiKey ? `https://texttospeech.googleapis.com/v1/text:synthesize?key=${encodeURIComponent(auth.apiKey)}` : "https://texttospeech.googleapis.com/v1/text:synthesize";
      const response = await fetch(endpoint, {
        method: "POST",
        signal: controller.signal,
        headers: {
          "content-type": "application/json",
          ...(auth.accessToken ? { authorization: `Bearer ${auth.accessToken}` } : {}),
          ...(auth.projectId ? { "x-goog-user-project": auth.projectId } : {}),
        },
        body: JSON.stringify({ input: { text }, voice, audioConfig: { audioEncoding: "MP3", speakingRate: 1.0, pitch: 0.0 } }),
      });
      const payload = await response.json().catch(() => null);
      if (!response.ok) {
        console.warn("case-voice Google TTS failed", response.status, String(payload?.error?.message ?? "").slice(0, 260));
        return null;
      }
      const audio = typeof payload?.audioContent === "string" ? payload.audioContent : "";
      if (!audio) return null;
      return { audio, voice: voice.name ?? "google-cloud-auto", languageCode: voice.languageCode };
    } catch (error) {
      const timeout = error instanceof DOMException && error.name === "AbortError";
      console.warn("case-voice Google TTS exception", timeout ? "timeout" : String(error));
      return null;
    } finally {
      clearTimeout(timer);
    }
  };
  const exact = await call(preferred);
  if (exact) return exact;
  if (preferred.name) return await call({ languageCode: preferred.languageCode, ssmlGender: preferred.ssmlGender ?? "MALE" });
  return null;
}

async function googleCloudSpeech(text: string, language: string) {
  const apiKey = Deno.env.get("GOOGLE_API_KEY")?.trim();
  if (apiKey) {
    const result = await requestGoogleCloudTts(text, language, { apiKey });
    if (result) return result;
  }
  const serviceAccount = await serviceAccountAccessToken();
  if (serviceAccount) {
    const result = await requestGoogleCloudTts(text, language, { accessToken: serviceAccount.token, projectId: serviceAccount.projectId });
    if (result) return result;
  }
  return null;
}

async function geminiSpeech(text: string, language: string) {
  const key = Deno.env.get("GEMINI_API_KEY")?.trim();
  if (!key) return null;
  const isArabic = shortLanguage(language) === "ar";
  const style = isArabic
    ? "SYNTHESIZE SPEECH ONLY. Speak as a real Egyptian male veterinarian from Cairo. Use natural Egyptian Arabic pronunciation and rhythm, warm, calm and professional, with realistic pauses and conversational intonation. Read the transcript exactly without adding, removing or paraphrasing words. Do not read these instructions aloud."
    : `SYNTHESIZE SPEECH ONLY. Read the transcript exactly in language ${language}, using a warm, natural, professional male veterinary-clinician delivery with realistic pauses and conversational intonation. Do not read these instructions aloud.`;
  const prompt = `${style}\n\nVERBATIM TRANSCRIPT START\n${text}\nVERBATIM TRANSCRIPT END`;
  const attempts = [
    { model: PRIMARY_GEMINI_MODEL, timeoutMs: 9000 },
    { model: FALLBACK_GEMINI_MODEL, timeoutMs: 9000 },
  ].filter((a, index, rows) => rows.findIndex((x) => x.model === a.model) === index);
  for (const attempt of attempts) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), attempt.timeoutMs);
    try {
      const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(attempt.model)}:generateContent`, {
        method: "POST",
        signal: controller.signal,
        headers: { "x-goog-api-key": key, "content-type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { responseModalities: ["AUDIO"], speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: "Sulafat" } } } },
        }),
      });
      const payload = await response.json().catch(() => null);
      if (!response.ok || !payload) {
        console.warn("case-voice Gemini attempt failed", attempt.model, response.status);
        continue;
      }
      const part = payload?.candidates?.[0]?.content?.parts?.find((p: any) => p?.inlineData?.data || p?.inline_data?.data);
      const rawBase64 = part?.inlineData?.data ?? part?.inline_data?.data;
      if (typeof rawBase64 !== "string" || !rawBase64) continue;
      const pcm = base64ToBytes(rawBase64);
      if (!pcm.length || pcm.length > 8 * 1024 * 1024) continue;
      return { audio: bytesToBase64(pcmToWav(pcm, 24000, 1, 16)), model: attempt.model, isArabic };
    } catch (error) {
      const timeout = error instanceof DOMException && error.name === "AbortError";
      console.warn("case-voice Gemini exception", attempt.model, timeout ? "timeout" : String(error));
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
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json({ error: "Invalid session" }, 401);
  const body = await req.json().catch(() => ({}));
  const text = sanitizeSpeechText(typeof body?.text === "string" ? body.text : "");
  const language = typeof body?.language === "string" && body.language.trim() ? body.language.trim().toLowerCase() : "en";
  if (!text) return json({ error: "Text is required" }, 400);

  const google = await googleCloudSpeech(text, language);
  if (google) {
    return json({ audio_base64: google.audio, mime_type: "audio/mpeg", provider: "google-cloud-tts", voice: google.voice, language_code: google.languageCode, requested_language: language });
  }

  const gemini = await geminiSpeech(text, language);
  if (gemini) {
    return json({ audio_base64: gemini.audio, mime_type: "audio/wav", provider: "gemini", voice: "Sulafat", model: gemini.model, egyptian_arabic_style: gemini.isArabic, requested_language: language });
  }

  return json({ code: "VOICE_TEMPORARILY_UNAVAILABLE" }, 503);
});