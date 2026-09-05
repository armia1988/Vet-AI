from pathlib import Path
import re


def replace_once(path: str, old: str, new: str, label: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'Missing marker for {label} in {path}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')
    print(f'patched: {label}')


# --- Faster scan upload ---
replace_once(
    'lib/v5_app.dart',
    """      imageQuality: 84,\n      maxWidth: 1600,\n""",
    """      imageQuality: 82,\n      maxWidth: 1400,\n      maxHeight: 1400,\n""",
    'scan image upload size',
)

# --- Speech cleanup: never read bullet/markdown markers as "point point point" ---
replace_once(
    'lib/analysis/vet_analysis_report.dart',
    """  Future<void> _speakCurrent() async {\n    if (_muted || !mounted) return;\n""",
    r'''  String _speechSafeText(String input) {
    var value = input
        .replaceAll(RegExp(r'https?://\S+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'www\.\S+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'[`*_#]+'), ' ')
        .replaceAll(RegExp(r'[•●▪◦‣⁃]+'), '. ')
        .replaceAll(RegExp(r'(^|\n)\s*[-–—]+\s*', multiLine: true), '. ')
        .replaceAll(RegExp(r'(^|\n)\s*\d+[\.)]\s*', multiLine: true), '. ')
        .replaceAll(RegExp(r'\s*\|\s*'), '. ')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    value = value.replaceAll(RegExp(r'(^[\s\.,;:]+|[\s,;:]+$)'), '');
    return value;
  }

  Future<void> _speakCurrent() async {
    if (_muted || !mounted) return;
''',
    'speech sanitizer helper',
)
replace_once(
    'lib/analysis/vet_analysis_report.dart',
    """    if (text.isEmpty) return;\n\n    try {\n""",
    """    text = _speechSafeText(text);\n    if (text.isEmpty) return;\n\n    try {\n""",
    'sanitize speech before all TTS paths',
)
replace_once(
    'lib/services/vet_case_workflow.dart',
    '.timeout(const Duration(seconds: 40));',
    '.timeout(const Duration(seconds: 18));',
    'voice network timeout',
)

# --- Faster, repeatable triage ---
analyze_path = Path('supabase/functions/analyze-case/index.ts')
text = analyze_path.read_text(encoding='utf-8')
old = 'const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_MODEL") ?? "gemini-3.6-flash";\nconst FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_FALLBACK_MODEL") ?? "gemini-3.5-flash-lite";'
new = 'const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_MODEL") ?? "gemini-3.5-flash-lite";\nconst FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_FALLBACK_MODEL") ?? "gemini-3.6-flash";'
if old not in text:
    raise SystemExit('analyze model marker missing')
text = text.replace(old, new, 1)
text = text.replace('      maxItems: 6,', '      maxItems: 4,', 1)
text = text.replace(
    '    immediate_actions: { type: "array", maxItems: 8, items: { type: "string" } },\n    follow_up_questions: { type: "array", maxItems: 6, items: { type: "string" } },',
    '    immediate_actions: { type: "array", maxItems: 5, items: { type: "string" } },\n    follow_up_questions: { type: "array", maxItems: 4, items: { type: "string" } },',
    1,
)
bytes_marker = '''const bytesToBase64 = (bytes: Uint8Array) => {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
  }
  return btoa(s);
};'''
bytes_replacement = bytes_marker + '''
const sha256Hex = async (bytes: Uint8Array) => {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
};
const sha256Text = (value: string) => sha256Hex(new TextEncoder().encode(value));'''
if bytes_marker not in text:
    raise SystemExit('analyze bytes helper marker missing')
text = text.replace(bytes_marker, bytes_replacement, 1)
text = text.replace(
    '.select("id,farm_id,media_path,symptom_notes,animal_group")',
    '.select("id,farm_id,media_path,symptom_notes,animal_group,ai_analysis,ai_model,ai_provider_request_id,ai_usage,ai_generated_at,status")',
    1,
)
image_marker = '''    const image = bytesToBase64(new Uint8Array(await blob.arrayBuffer()));

    const languageInstruction = ar'''
image_replacement = '''    const imageBytes = new Uint8Array(await blob.arrayBuffer());
    const image = bytesToBase64(imageBytes);
    const imageSha256 = await sha256Hex(imageBytes);
    const catalogSha256 = await sha256Text(JSON.stringify(modelCatalog));
    const normalizedNotes = clean(assessment.symptom_notes).toLowerCase();
    const inputFingerprint = await sha256Text(`${imageSha256}|${animalGroup}|${language}|${normalizedNotes}|${catalogSha256}`);

    // Exact same image + history + language + reviewed catalog should not jump
    // between diseases on repeated tests or spend provider quota again.
    if (assessment.ai_analysis?.input_fingerprint === inputFingerprint && assessment.ai_analysis?.code === "AI_ANALYSIS_COMPLETE") {
      return json({ ...assessment.ai_analysis, cache_reused: true });
    }
    const { data: cachedRows } = await supabase
      .from("assessments")
      .select("id,ai_analysis,ai_model,ai_provider_request_id,ai_usage,ai_generated_at")
      .eq("farm_id", assessment.farm_id)
      .eq("animal_group", animalGroup)
      .neq("id", assessmentId)
      .eq("ai_analysis->>input_fingerprint", inputFingerprint)
      .order("ai_generated_at", { ascending: false })
      .limit(1);
    const cachedRow = cachedRows?.[0];
    if (cachedRow?.ai_analysis?.code === "AI_ANALYSIS_COMPLETE") {
      const cached = {
        ...cachedRow.ai_analysis,
        assessment_id: assessmentId,
        cache_reused: true,
        cache_source_assessment_id: cachedRow.id,
        generated_at: new Date().toISOString(),
      };
      await supabase.from("assessments").update({
        observed_signs: cached.observed_signs ?? [],
        differential_diagnoses: cached.differential_diagnoses ?? [],
        risk: cached.risk ?? "insufficient_data",
        isolation_recommended: cached.isolation_recommended === true,
        urgent_vet_review: cached.urgent_vet_review === true,
        lab_confirmation_required: cached.lab_confirmation_required === true,
        status: "ai_review",
        ai_analysis: cached,
        ai_model: cachedRow.ai_model,
        ai_provider_request_id: cachedRow.ai_provider_request_id,
        ai_usage: { ...(cachedRow.ai_usage ?? {}), cache_reused: true, cache_source_assessment_id: cachedRow.id },
        ai_generated_at: cached.generated_at,
      }).eq("id", assessmentId);
      await supabase.from("alerts").delete().eq("assessment_id", assessmentId);
      if (cached.risk === "red" || cached.risk === "orange") {
        await supabase.from("alerts").insert({
          farm_id: assessment.farm_id,
          assessment_id: assessmentId,
          risk: cached.risk,
          title: ar
            ? (cached.risk === "red" ? "تنبيه صحي عاجل من Vet AI" : "حالة محتاجة مراجعة بيطرية")
            : (cached.risk === "red" ? "Urgent Vet AI health alert" : "Vet AI veterinary review alert"),
          details: cached.summary ?? "",
        });
      }
      return json(cached);
    }

    const languageInstruction = ar'''
if image_marker not in text:
    raise SystemExit('analyze image marker missing')
text = text.replace(image_marker, image_replacement, 1)
prompt_old = 'Analyze the image conservatively. Verify the animal group first. Never claim a definitive diagnosis from one image. Only report signs actually visible. High-consequence diseases require compatible evidence and veterinary/laboratory confirmation. Never invent medication doses or withdrawal periods.'
prompt_new = 'Analyze the image conservatively. Verify the animal group first. Never claim a definitive diagnosis from one image. Only report signs actually visible. Rank differentials ONLY by compatibility with visible signs plus supplied history. Do not choose a disease just because it is common. If evidence is weak or two conditions are similarly plausible, keep suspicion low/moderate and state uncertainty instead of arbitrarily switching the top disease. Return no more than four differentials. High-consequence diseases require compatible evidence and veterinary/laboratory confirmation. Never invent medication doses or withdrawal periods.'
if prompt_old not in text:
    raise SystemExit('analyze prompt marker missing')
text = text.replace(prompt_old, prompt_new, 1)
gen_old = '''              temperature: 0.1,
              maxOutputTokens: 5200,
              responseMimeType: "application/json",'''
gen_new = '''              candidateCount: 1,
              seed: parseInt(inputFingerprint.slice(0, 8), 16) & 0x7fffffff,
              maxOutputTokens: 2200,
              thinkingConfig: { thinkingLevel: "low" },
              responseMimeType: "application/json",'''
if gen_old not in text:
    raise SystemExit('analyze generation marker missing')
text = text.replace(gen_old, gen_new, 1)
text = text.replace(
    '      { model: PRIMARY_MODEL, timeoutMs: 22000 },\n      { model: FALLBACK_MODEL, timeoutMs: 18000 },',
    '      { model: PRIMARY_MODEL, timeoutMs: 9500 },\n      { model: FALLBACK_MODEL, timeoutMs: 10500 },',
    1,
)
text = text.replace('      .slice(0, 6)\n      .map((d: any) => {', '      .slice(0, 4)\n      .map((d: any) => {', 1)
sort_marker = '''      });

    const groupMatch ='''
sort_replacement = '''      })
      .sort((a: any, b: any) => {
        const rank: Record<string, number> = { high: 3, moderate: 2, low: 1 };
        const delta = (rank[b.suspicion] ?? 0) - (rank[a.suspicion] ?? 0);
        return delta || String(a.catalog_slug).localeCompare(String(b.catalog_slug));
      });

    const groupMatch ='''
if sort_marker not in text:
    raise SystemExit('analyze differential sort marker missing')
text = text.replace(sort_marker, sort_replacement, 1)
text = text.replace(
    '      failover_used: usedModel !== PRIMARY_MODEL,\n      generated_at:',
    '      failover_used: usedModel !== PRIMARY_MODEL,\n      input_fingerprint: inputFingerprint,\n      image_sha256: imageSha256,\n      generated_at:',
    1,
)
analyze_path.write_text(text, encoding='utf-8')
print('patched: analyze-case speed/cache/stability')

# --- Faster final report with stable seed ---
final_path = Path('supabase/functions/finalize-case-report/index.ts')
text = final_path.read_text(encoding='utf-8')
old = 'const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_MODEL") ?? "gemini-3.6-flash";\nconst FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_FALLBACK_MODEL") ?? "gemini-3.5-flash-lite";'
new = 'const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_MODEL") ?? "gemini-3.5-flash-lite";\nconst FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_FALLBACK_MODEL") ?? "gemini-3.6-flash";'
if old not in text:
    raise SystemExit('final model marker missing')
text = text.replace(old, new, 1)
gen_old = '''                temperature: 0.1,
                maxOutputTokens: 5200,
                responseMimeType: "application/json",'''
gen_new = '''                candidateCount: 1,
                seed: parseInt(fingerprint.slice(0, 8), 16) & 0x7fffffff,
                maxOutputTokens: 3200,
                thinkingConfig: { thinkingLevel: "low" },
                responseMimeType: "application/json",'''
if gen_old not in text:
    raise SystemExit('final generation marker missing')
text = text.replace(gen_old, gen_new, 1)
text = text.replace(
    '        { model: PRIMARY_MODEL, timeoutMs: 22000 },\n        { model: FALLBACK_MODEL, timeoutMs: 16000 },',
    '        { model: PRIMARY_MODEL, timeoutMs: 11000 },\n        { model: FALLBACK_MODEL, timeoutMs: 12000 },',
    1,
)
final_path.write_text(text, encoding='utf-8')
print('patched: final report speed/stability')

# --- Natural voice: sanitize input + Google Cloud TTS fallback when enabled ---
voice_path = Path('supabase/functions/case-voice/index.ts')
text = voice_path.read_text(encoding='utf-8')
voice_input_old = '''  const rawText = typeof body?.text === "string" ? body.text.trim() : "";
  const text = rawText.slice(0, 1800);'''
voice_input_new = '''  const rawText = typeof body?.text === "string" ? body.text.trim() : "";
  const text = rawText
    .replace(/https?:\\/\\/\\S+/gi, " ")
    .replace(/www\\.\\S+/gi, " ")
    .replace(/[`*_#]+/g, " ")
    .replace(/[•●▪◦‣⁃]+/g, ". ")
    .replace(/(^|\\n)\\s*[-–—]+\\s*/gm, ". ")
    .replace(/(^|\\n)\\s*\\d+[.)]\\s*/gm, ". ")
    .replace(/\\s+/g, " ")
    .trim()
    .slice(0, 1500);'''
if voice_input_old not in text:
    raise SystemExit('voice input marker missing')
text = text.replace(voice_input_old, voice_input_new, 1)
text = text.replace(
    '    { model: PRIMARY_MODEL, timeoutMs: 18000 },\n    { model: FALLBACK_MODEL, timeoutMs: 18000 },',
    '    { model: PRIMARY_MODEL, timeoutMs: 8000 },\n    { model: FALLBACK_MODEL, timeoutMs: 7000 },',
    1,
)
end_marker = '''  return json({ code: "GEMINI_TTS_TEMPORARILY_UNAVAILABLE" }, 503);
});'''
cloud_fallback = '''  // Reliability fallback: if Gemini native TTS is temporarily unavailable,
  // use Google Cloud Text-to-Speech when that API is enabled for this key/project.
  // The Flutter app never receives or stores the secret key.
  const cloudKey = Deno.env.get("GOOGLE_CLOUD_TTS_API_KEY") ?? Deno.env.get("GOOGLE_API_KEY") ?? key;
  if (cloudKey) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 6500);
      try {
        const cloudResponse = await fetch(`https://texttospeech.googleapis.com/v1/text:synthesize?key=${encodeURIComponent(cloudKey)}`, {
          method: "POST",
          signal: controller.signal,
          headers: { "content-type": "application/json" },
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
    } catch (error) {
      console.warn("case-voice Cloud TTS fallback exception", String(error));
    }
  }

  return json({ code: "VOICE_TEMPORARILY_UNAVAILABLE" }, 503);
});'''
if end_marker not in text:
    raise SystemExit('voice end marker missing')
text = text.replace(end_marker, cloud_fallback, 1)
voice_path.write_text(text, encoding='utf-8')
print('patched: case-voice cleanup and Cloud TTS fallback')

replace_once('pubspec.yaml', 'version: 0.6.11+23', 'version: 0.6.12+24', 'V26 app version')
