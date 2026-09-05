from pathlib import Path
import re

# Deno 2 WebCrypto requires an ArrayBuffer-backed BufferSource.
p = Path('supabase/functions/analyze-case/index.ts')
text = p.read_text(encoding='utf-8')
old = '''const sha256Hex = async (bytes: Uint8Array) => {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
};'''
new = '''const sha256Hex = async (bytes: Uint8Array) => {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", copy.buffer);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
};'''
if old not in text:
    raise SystemExit('sha256 helper marker missing')
p.write_text(text.replace(old, new, 1), encoding='utf-8')
print('patched: Deno WebCrypto SHA-256 typing')

# Replace the API-key Cloud TTS idea with the supported production auth path.
# Cloud Text-to-Speech requires Google Cloud OAuth credentials. If the optional
# service-account secret is not configured, Gemini native TTS remains primary
# and Flutter falls back locally without exposing any server credential.
p = Path('supabase/functions/case-voice/index.ts')
text = p.read_text(encoding='utf-8')
start = text.find('  // Reliability fallback: if Gemini native TTS is temporarily unavailable,')
end_marker = '  return json({ code: "VOICE_TEMPORARILY_UNAVAILABLE" }, 503);\n});'
end = text.find(end_marker)
if start < 0 or end < 0:
    raise SystemExit('Cloud fallback block markers missing')

replacement = r'''  // Optional production fallback through Google Cloud Text-to-Speech.
  // Google Cloud TTS is OAuth-authenticated; do not send the Gemini API key to it.
  const serviceAccountRaw = Deno.env.get("GOOGLE_CLOUD_TTS_SERVICE_ACCOUNT_JSON");
  if (serviceAccountRaw) {
    try {
      const sa = JSON.parse(serviceAccountRaw);
      const clientEmail = String(sa?.client_email ?? "");
      const privateKeyPem = String(sa?.private_key ?? "");
      const projectId = String(sa?.project_id ?? "");
      if (clientEmail && privateKeyPem) {
        const base64Url = (bytes: Uint8Array) => {
          let raw = "";
          for (let i = 0; i < bytes.length; i += 0x8000) {
            raw += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
          }
          return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
        };
        const utf8Base64Url = (value: string) => base64Url(new TextEncoder().encode(value));
        const pemBody = privateKeyPem
          .replace(/-----BEGIN PRIVATE KEY-----/g, "")
          .replace(/-----END PRIVATE KEY-----/g, "")
          .replace(/\s+/g, "");
        const pemBinary = atob(pemBody);
        const pemBytes = new Uint8Array(pemBinary.length);
        for (let i = 0; i < pemBinary.length; i++) pemBytes[i] = pemBinary.charCodeAt(i);
        const signingKey = await crypto.subtle.importKey(
          "pkcs8",
          pemBytes.buffer,
          { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
          false,
          ["sign"],
        );
        const now = Math.floor(Date.now() / 1000);
        const jwtHeader = utf8Base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
        const jwtPayload = utf8Base64Url(JSON.stringify({
          iss: clientEmail,
          scope: "https://www.googleapis.com/auth/cloud-platform",
          aud: "https://oauth2.googleapis.com/token",
          iat: now,
          exp: now + 3300,
        }));
        const unsigned = `${jwtHeader}.${jwtPayload}`;
        const signature = await crypto.subtle.sign(
          "RSASSA-PKCS1-v1_5",
          signingKey,
          new TextEncoder().encode(unsigned),
        );
        const assertion = `${unsigned}.${base64Url(new Uint8Array(signature))}`;
        const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
          method: "POST",
          headers: { "content-type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
            assertion,
          }),
        });
        const tokenPayload = await tokenResponse.json().catch(() => null);
        const accessToken = typeof tokenPayload?.access_token === "string" ? tokenPayload.access_token : "";
        if (tokenResponse.ok && accessToken) {
          const controller = new AbortController();
          const timer = setTimeout(() => controller.abort(), 6500);
          try {
            const cloudResponse = await fetch("https://texttospeech.googleapis.com/v1/text:synthesize", {
              method: "POST",
              signal: controller.signal,
              headers: {
                authorization: `Bearer ${accessToken}`,
                "content-type": "application/json",
                ...(projectId ? { "x-goog-user-project": projectId } : {}),
              },
              body: JSON.stringify({
                input: { text },
                voice: isArabic
                  ? { languageCode: "ar-XA", name: "ar-XA-Chirp3-HD-Sulafat", ssmlGender: "FEMALE" }
                  : { languageCode: languageCode(language), ssmlGender: "FEMALE" },
                audioConfig: { audioEncoding: "MP3", speakingRate: 1.0 },
              }),
            });
            const cloudPayload = await cloudResponse.json().catch(() => null);
            const audioContent = cloudPayload?.audioContent;
            if (cloudResponse.ok && typeof audioContent === "string" && audioContent) {
              return json({
                audio_base64: audioContent,
                mime_type: "audio/mpeg",
                voice: isArabic ? "ar-XA-Chirp3-HD-Sulafat" : "google-cloud-auto",
                provider: "google-cloud-tts",
                egyptian_arabic_text: isArabic,
              });
            }
            console.warn("case-voice Cloud TTS fallback failed", cloudResponse.status, String(cloudPayload?.error?.message ?? "").slice(0, 350));
          } finally {
            clearTimeout(timer);
          }
        } else {
          console.warn("case-voice OAuth token exchange failed", tokenResponse.status, String(tokenPayload?.error_description ?? tokenPayload?.error ?? "").slice(0, 350));
        }
      }
    } catch (error) {
      console.warn("case-voice Cloud TTS service-account fallback exception", String(error));
    }
  }

  return json({ code: "VOICE_TEMPORARILY_UNAVAILABLE" }, 503);
});'''
text = text[:start] + replacement + text[end + len(end_marker):]
p.write_text(text, encoding='utf-8')
print('patched: supported Google Cloud TTS OAuth fallback')
