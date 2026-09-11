import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_MODEL") ?? "gemini-3.6-flash";
const FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_FALLBACK_MODEL") ?? "gemini-3.5-flash-lite";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    image_quality: { type: "string", enum: ["insufficient", "limited", "adequate"] },
    trend: { type: "string", enum: ["better", "same", "worse", "uncertain"] },
    visual_change_summary: { type: "string" },
    symptom_change_summary: { type: "string" },
    temperature_interpretation: { type: "string" },
    red_flags: { type: "array", maxItems: 8, items: { type: "string" } },
    urgent_vet_review: { type: "boolean" },
    next_actions: { type: "array", maxItems: 6, items: { type: "string" } },
    confidence_statement: { type: "string" },
  },
  required: [
    "image_quality",
    "trend",
    "visual_change_summary",
    "symptom_change_summary",
    "temperature_interpretation",
    "red_flags",
    "urgent_vet_review",
    "next_actions",
    "confidence_statement",
  ],
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });

const clean = (value: unknown) => String(value ?? "").replace(/https?:\/\/\S+/gi, "").replace(/\s{2,}/g, " ").trim();
const cleanList = (value: unknown) => Array.isArray(value) ? value.map(clean).filter(Boolean) : [];

const mimeFromPath = (path: string) => {
  const ext = path.split(".").pop()?.toLowerCase();
  if (ext === "jpg" || ext === "jpeg") return "image/jpeg";
  if (ext === "png") return "image/png";
  if (ext === "webp") return "image/webp";
  return null;
};

const bytesToBase64 = (bytes: Uint8Array) => {
  let text = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    text += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
  }
  return btoa(text);
};

const modelText = (payload: any) => {
  for (const candidate of payload?.candidates ?? []) {
    const chunks: string[] = [];
    for (const part of candidate?.content?.parts ?? []) {
      if (part?.thought === true) continue;
      if (typeof part?.text === "string" && part.text.length) chunks.push(part.text);
    }
    if (chunks.length) return chunks.join("").trim();
  }
  return null;
};

const parseJson = (raw: string) => {
  const value = raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  try {
    return JSON.parse(value);
  } catch (_) {}
  const first = value.indexOf("{");
  const last = value.lastIndexOf("}");
  if (first >= 0 && last > first) return JSON.parse(value.slice(first, last + 1));
  throw new Error("No complete JSON response");
};

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ error: "missing_authorization" }, 401);

    const body = await req.json().catch(() => ({}));
    const followupId = typeof body?.followup_id === "string" ? body.followup_id : "";
    const language = typeof body?.language === "string" ? body.language.toLowerCase() : "en";
    if (!followupId) return json({ error: "followup_id_required" }, 400);

    const key = Deno.env.get("GEMINI_API_KEY")?.trim();
    if (!key) return json({ error: "gemini_not_configured" }, 503);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );

    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) return json({ error: "invalid_session" }, 401);

    const { data: followup, error: followupError } = await supabase
      .from("animal_ai_followups")
      .select("id,farm_id,animal_id,assessment_id,offset_hours,media_path,symptom_notes,temperature_c,status")
      .eq("id", followupId)
      .single();
    if (followupError || !followup) return json({ error: "followup_not_found" }, 404);
    if (!followup.media_path) return json({ error: "followup_image_required" }, 400);

    const { data: baseline, error: baselineError } = await supabase
      .from("assessments")
      .select("id,media_path,symptom_notes,ai_analysis,risk,ai_generated_at,species_code,bird_type")
      .eq("id", followup.assessment_id)
      .single();
    if (baselineError || !baseline || !baseline.media_path) {
      return json({ error: "baseline_assessment_unavailable" }, 404);
    }

    const [baselineBlobResult, currentBlobResult] = await Promise.all([
      supabase.storage.from("diagnostic-media").download(baseline.media_path),
      supabase.storage.from("diagnostic-media").download(followup.media_path),
    ]);
    if (baselineBlobResult.error || !baselineBlobResult.data) return json({ error: "baseline_image_unavailable" }, 404);
    if (currentBlobResult.error || !currentBlobResult.data) return json({ error: "followup_image_unavailable" }, 404);
    if (baselineBlobResult.data.size > MAX_IMAGE_BYTES || currentBlobResult.data.size > MAX_IMAGE_BYTES) {
      return json({ error: "image_too_large" }, 400);
    }

    const baselineMime = mimeFromPath(baseline.media_path);
    const currentMime = mimeFromPath(followup.media_path);
    if (!baselineMime || !currentMime) return json({ error: "unsupported_image_format" }, 400);

    const baselineImage = bytesToBase64(new Uint8Array(await baselineBlobResult.data.arrayBuffer()));
    const currentImage = bytesToBase64(new Uint8Array(await currentBlobResult.data.arrayBuffer()));

    const baselineAi = baseline.ai_analysis && typeof baseline.ai_analysis === "object" ? baseline.ai_analysis : {};
    const baselineSummary = clean((baselineAi as any)?.summary ?? baseline.symptom_notes ?? "");
    const species = clean(baseline.species_code || baseline.bird_type || "animal");
    const currentNotes = clean(followup.symptom_notes);
    const temperature = followup.temperature_c == null ? "not supplied" : `${followup.temperature_c} °C`;
    const languageRule = language.startsWith("ar")
      ? "Write every user-facing field in professional Egyptian Arabic only."
      : `Write every user-facing field naturally in language code ${language}.`;

    const prompt = `You are Vet AI performing a FOLLOW-UP comparison, not a new diagnosis. ${languageRule}\n
Species: ${species}\n
Follow-up time: ${followup.offset_hours} hours after the original AI assessment.\n
Original risk: ${baseline.risk}\n
Original AI summary: ${baselineSummary || "No baseline summary supplied"}\n
Current owner notes: ${currentNotes || "No current symptom notes supplied"}\n
Current temperature: ${temperature}\n

You receive TWO images in order: IMAGE 1 is the original baseline image and IMAGE 2 is the new follow-up image. Compare only visible changes that can be supported by the images and supplied observations. Evaluate whether visible lesion burden, swelling, redness, discharge, crusting, wounds, posture, or other visible abnormalities appear better, unchanged, worse, or uncertain. Do not invent measurements. Do not claim disease cure or definitive diagnosis. Temperature interpretation must be conservative because normal ranges vary by species and measurement method. If image quality, angle, lighting, or framing prevents reliable comparison, choose uncertain. If there are worsening visible signs, major new red flags, or the supplied symptoms indicate deterioration, flag urgent veterinary review. Never provide medication doses or withdrawal periods.`;

    const callModel = async (model: string, timeoutMs: number) => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const response = await fetch(`${BASE}/${encodeURIComponent(model)}:generateContent`, {
          method: "POST",
          signal: controller.signal,
          headers: { "x-goog-api-key": key, "content-type": "application/json" },
          body: JSON.stringify({
            contents: [{
              role: "user",
              parts: [
                { text: prompt },
                { text: "IMAGE 1 — original baseline" },
                { inline_data: { mime_type: baselineMime, data: baselineImage } },
                { text: "IMAGE 2 — current follow-up" },
                { inline_data: { mime_type: currentMime, data: currentImage } },
              ],
            }],
            generationConfig: {
              temperature: 0.05,
              maxOutputTokens: 2200,
              responseMimeType: "application/json",
              responseJsonSchema: SCHEMA,
            },
          }),
        });
        const payload = await response.json().catch(() => null);
        return { response, payload };
      } finally {
        clearTimeout(timer);
      }
    };

    let parsed: any = null;
    let usedModel = "";
    const attempts: string[] = [];
    for (const attempt of [
      { model: PRIMARY_MODEL, timeout: 24000 },
      { model: FALLBACK_MODEL, timeout: 20000 },
    ].filter((item, index, list) => list.findIndex((x) => x.model === item.model) === index)) {
      try {
        const result = await callModel(attempt.model, attempt.timeout);
        if (!result.response.ok || !result.payload) {
          attempts.push(`${attempt.model}:${result.response.status}`);
          continue;
        }
        const raw = modelText(result.payload);
        try {
          parsed = raw ? parseJson(raw) : null;
        } catch (_) {
          parsed = null;
        }
        if (parsed) {
          usedModel = attempt.model;
          break;
        }
        attempts.push(`${attempt.model}:invalid_json`);
      } catch (error) {
        attempts.push(`${attempt.model}:${error instanceof DOMException && error.name === "AbortError" ? "timeout" : "exception"}`);
      }
    }

    if (!parsed || !usedModel) {
      return json({ error: "followup_analysis_unavailable", attempts }, 503);
    }

    const trend = ["better", "same", "worse", "uncertain"].includes(parsed.trend) ? parsed.trend : "uncertain";
    const result = {
      code: "AI_FOLLOWUP_COMPLETE",
      followup_id: followupId,
      assessment_id: followup.assessment_id,
      offset_hours: followup.offset_hours,
      trend,
      image_quality: ["insufficient", "limited", "adequate"].includes(parsed.image_quality) ? parsed.image_quality : "limited",
      visual_change_summary: clean(parsed.visual_change_summary),
      symptom_change_summary: clean(parsed.symptom_change_summary),
      temperature_interpretation: clean(parsed.temperature_interpretation),
      red_flags: cleanList(parsed.red_flags).slice(0, 8),
      urgent_vet_review: parsed.urgent_vet_review === true,
      next_actions: cleanList(parsed.next_actions).slice(0, 6),
      confidence_statement: clean(parsed.confidence_statement),
      model: usedModel,
      generated_at: new Date().toISOString(),
    };

    const { error: saveError } = await supabase
      .from("animal_ai_followups")
      .update({
        status: "completed",
        outcome: result.trend,
        ai_comparison: result,
        ai_model: usedModel,
        ai_generated_at: result.generated_at,
        completed_at: result.generated_at,
      })
      .eq("id", followupId);
    if (saveError) return json({ error: "followup_result_save_failed" }, 500);

    if (result.trend === "worse" || result.urgent_vet_review) {
      await supabase.from("alerts").insert({
        farm_id: followup.farm_id,
        animal_id: followup.animal_id,
        risk: "yellow",
        title: "Vet AI follow-up needs attention",
        details: result.visual_change_summary || result.symptom_change_summary || "Follow-up comparison suggests deterioration or veterinary review.",
        source: "ai_followup",
        metric: "followup_worse",
      });
    }

    return json(result);
  } catch (error) {
    console.error("analyze-followup failed", error);
    return json({ error: "followup_internal_error" }, 500);
  }
});
