import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_MODEL") ?? "gemini-3.6-flash";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

const ANALYSIS_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    image_quality: { type: "string", enum: ["insufficient", "limited", "adequate"] },
    group_match: { type: "string", enum: ["match", "mismatch", "uncertain"] },
    group_match_reason: { type: "string" },
    species_observed: { type: "string" },
    summary: { type: "string" },
    observed_signs: { type: "array", maxItems: 12, items: { type: "string" } },
    differentials: {
      type: "array",
      maxItems: 6,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          catalog_slug: { type: "string" },
          display_name: { type: "string" },
          suspicion: { type: "string", enum: ["low", "moderate", "high"] },
          reasoning: { type: "string" },
        },
        required: ["catalog_slug", "display_name", "suspicion", "reasoning"],
      },
    },
    risk: { type: "string", enum: ["none", "yellow", "orange", "red", "insufficient_data"] },
    urgent_vet_review: { type: "boolean" },
    isolation_recommended: { type: "boolean" },
    lab_confirmation_required: { type: "boolean" },
    immediate_actions: { type: "array", maxItems: 8, items: { type: "string" } },
    follow_up_questions: { type: "array", maxItems: 6, items: { type: "string" } },
    confidence_statement: { type: "string" },
  },
  required: [
    "image_quality", "group_match", "group_match_reason", "species_observed", "summary",
    "observed_signs", "differentials", "risk", "urgent_vet_review", "isolation_recommended",
    "lab_confirmation_required", "immediate_actions", "follow_up_questions", "confidence_statement",
  ],
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});
const fail = (code: string, message: string, status = 200, extra: Record<string, unknown> = {}) =>
  json({ code, risk: "insufficient_data", message, ...extra }, status);
const clean = (v: unknown) => String(v ?? "").replace(/https?:\/\/\S+/gi, "").replace(/\s{2,}/g, " ").trim();
const cleanList = (v: unknown) => Array.isArray(v) ? v.map(clean).filter(Boolean) : [];
const mimeFromPath = (path: string) => {
  const ext = path.split(".").pop()?.toLowerCase();
  if (ext === "jpg" || ext === "jpeg") return "image/jpeg";
  if (ext === "png") return "image/png";
  if (ext === "webp") return "image/webp";
  return null;
};
const bytesToBase64 = (bytes: Uint8Array) => {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    s += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
  }
  return btoa(s);
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

const parseJsonSafely = (raw: string) => {
  const value = raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  try { return JSON.parse(value); } catch (_) {}
  const first = value.indexOf("{");
  const last = value.lastIndexOf("}");
  if (first >= 0 && last > first) return JSON.parse(value.slice(first, last + 1));
  throw new Error("No complete JSON object in Gemini response");
};

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ error: "Missing authorization" }, 401);

    const body = await req.json().catch(() => ({}));
    const assessmentId = typeof body?.assessment_id === "string" ? body.assessment_id : "";
    const language = typeof body?.language === "string" ? body.language.toLowerCase() : "en";
    const ar = language.startsWith("ar");
    if (!assessmentId) return json({ error: "assessment_id is required" }, 400);

    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) return fail("GEMINI_NOT_CONFIGURED", ar ? "مفتاح Gemini غير متاح لخدمة التحليل." : "Gemini API key is not available.", 503);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } },
    );

    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

    const { data: assessment, error: assessmentError } = await supabase
      .from("assessments")
      .select("id,farm_id,media_path,symptom_notes,animal_group")
      .eq("id", assessmentId)
      .single();
    if (assessmentError || !assessment) return json({ error: "Assessment not found or access denied" }, 404);
    if (!assessment.media_path) return json({ error: "Assessment has no image" }, 400);
    const animalGroup = assessment.animal_group ?? "livestock";

    const { data: allDiseases, error: diseaseError } = await supabase
      .from("disease_catalog")
      .select("id,slug,display_name,animal_groups,cause,default_risk,treatment_summary,prevention_summary,owner_actions_summary,clinical_red_flags,isolation_guidance,lab_confirmation_required,zoonotic,reportable_or_listed,curation_status")
      .eq("curation_status", "reviewed")
      .order("display_name");
    if (diseaseError || !allDiseases) {
      return fail("KNOWLEDGE_BASE_UNAVAILABLE", ar ? "قاعدة المعرفة البيطرية غير متاحة مؤقتًا." : "Veterinary knowledge base is temporarily unavailable.");
    }

    const diseases = allDiseases.filter((d: any) => Array.isArray(d.animal_groups) && d.animal_groups.includes(animalGroup));
    if (!diseases.length) {
      return fail("KNOWLEDGE_GAP", ar ? "لا توجد معرفة بيطرية مراجعة كافية للنوع المختار." : "No reviewed veterinary knowledge is available for this animal group.");
    }

    const ids = diseases.map((d: any) => d.id);
    const { data: signs } = await supabase
      .from("disease_signs")
      .select("disease_id,phase,sign,visible_in_image")
      .in("disease_id", ids);

    const modelCatalog = diseases.map((d: any) => ({
      slug: d.slug,
      name: d.display_name,
      cause: d.cause,
      default_risk: d.default_risk,
      lab_confirmation_required: d.lab_confirmation_required,
      zoonotic: d.zoonotic,
      reportable_or_listed: d.reportable_or_listed,
      visible_signs: (signs ?? [])
        .filter((s: any) => s.disease_id === d.id && s.visible_in_image === true)
        .map((s: any) => ({ phase: s.phase, sign: s.sign })),
    }));

    const { data: blob, error: mediaError } = await supabase.storage.from("diagnostic-media").download(assessment.media_path);
    if (mediaError || !blob) return json({ error: "Image unavailable or access denied" }, 404);
    if (blob.size > MAX_IMAGE_BYTES) return fail("IMAGE_TOO_LARGE", ar ? "الصورة كبيرة جدًا للتحليل." : "Image is too large for analysis.");
    const mime = mimeFromPath(assessment.media_path);
    if (!mime) return fail("UNSUPPORTED_IMAGE_FORMAT", ar ? "استخدم صورة JPEG أو PNG أو WEBP." : "Use JPEG, PNG or WEBP.");
    const image = bytesToBase64(new Uint8Array(await blob.arrayBuffer()));

    const languageInstruction = ar
      ? "اكتب كل الحقول التي يراها المستخدم بالعربية المصرية الواضحة والمهنية، من غير خلط جمل إنجليزية."
      : `Write every user-facing field naturally in language code ${language}.`;
    const prompt = `You are Vet AI, a veterinary decision-support triage system. You are not a substitute for a veterinarian. ${languageInstruction}\n\nSelected animal group: ${animalGroup}\nSymptoms/history: ${assessment.symptom_notes?.trim() || "None supplied"}\n\nReviewed disease catalog. ONLY these catalog_slug values may be returned:\n${JSON.stringify(modelCatalog)}\n\nAnalyze the image conservatively. Verify the animal group first. Never claim a definitive diagnosis from one image. Only report signs that are actually visible. High-consequence diseases require compatible evidence and veterinary/laboratory confirmation. Do not invent medication doses or withdrawal periods.`;

    const callGemini = async (maxOutputTokens: number) => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 45000);
      try {
        const response = await fetch(`${BASE}/${encodeURIComponent(MODEL)}:generateContent`, {
          method: "POST",
          signal: controller.signal,
          headers: { "x-goog-api-key": key, "content-type": "application/json" },
          body: JSON.stringify({
            contents: [{ role: "user", parts: [{ text: prompt }, { inline_data: { mime_type: mime, data: image } }] }],
            generationConfig: {
              maxOutputTokens,
              thinkingConfig: { thinkingLevel: "low" },
              responseMimeType: "application/json",
              responseJsonSchema: ANALYSIS_SCHEMA,
            },
          }),
        });
        const payload = await response.json().catch(() => null);
        return { response, payload };
      } finally {
        clearTimeout(timer);
      }
    };

    const providerFailure = (response: Response, payload: any, requestId: string) => {
      const providerStatus = String(payload?.error?.status ?? "");
      const providerMessage = String(payload?.error?.message ?? "");
      console.error("Vet AI Gemini provider error", response.status, providerStatus, requestId, providerMessage.slice(0, 500));
      if (response.status === 401 || response.status === 403 || providerStatus === "PERMISSION_DENIED" || providerStatus === "UNAUTHENTICATED") {
        return fail("GEMINI_AUTH_ERROR", ar ? "Gemini رفض مفتاح الـAPI أو صلاحياته." : "Gemini rejected the API key or permissions.", 502, { provider_request_id: requestId });
      }
      if (response.status === 404 || providerStatus === "NOT_FOUND") {
        return fail("GEMINI_MODEL_UNAVAILABLE", ar ? "نموذج Gemini المحدد غير متاح للحساب." : "The configured Gemini model is unavailable for this account.", 502, { provider_request_id: requestId });
      }
      if (response.status === 429 || providerStatus === "RESOURCE_EXHAUSTED") {
        return fail("GEMINI_RATE_LIMIT", ar ? "Gemini وصل لحد استخدام مؤقت. حاول بعد وقت قصير." : "Gemini reached a temporary usage limit.", 429, { provider_request_id: requestId });
      }
      return fail("GEMINI_PROVIDER_ERROR", ar ? "Gemini لم يتمكن من إكمال التحليل الآن." : "Gemini could not complete the analysis.", 502, { provider_request_id: requestId, provider_status: response.status });
    };

    let first;
    try {
      first = await callGemini(8192);
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") {
        return fail("GEMINI_TIMEOUT", ar ? "Gemini أخذ وقتًا أطول من المتوقع. جرّب مرة أخرى." : "Gemini took longer than expected. Please retry.", 504);
      }
      throw e;
    }

    let response = first.response;
    let payload = first.payload;
    let requestId = String(payload?.responseId ?? response.headers.get("x-request-id") ?? "");
    if (!response.ok || !payload) return providerFailure(response, payload, requestId);

    const firstFinish = String(payload?.candidates?.[0]?.finishReason ?? "");
    if (["SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT"].includes(firstFinish) || payload?.promptFeedback?.blockReason) {
      return fail("GEMINI_SAFETY_STOP", ar ? "Gemini أوقف التحليل بسبب فلتر أمان. استخدم صورة أوضح للحيوان فقط من غير محتوى غير متعلق بالحالة." : "Gemini stopped the analysis because of a safety filter.", 422, { provider_request_id: requestId });
    }

    let raw = modelText(payload);
    let parsed: any = null;
    if (raw) {
      try { parsed = parseJsonSafely(raw); } catch (_) {}
    }

    if (!parsed || firstFinish === "MAX_TOKENS") {
      console.warn("Vet AI Gemini structured retry", requestId, firstFinish, raw?.length ?? 0, payload?.usageMetadata ?? {});
      let second;
      try {
        second = await callGemini(14000);
      } catch (e) {
        if (e instanceof DOMException && e.name === "AbortError") {
          return fail("GEMINI_TIMEOUT", ar ? "Gemini أخذ وقتًا أطول من المتوقع. جرّب مرة أخرى." : "Gemini took longer than expected. Please retry.", 504);
        }
        throw e;
      }
      response = second.response;
      payload = second.payload;
      requestId = String(payload?.responseId ?? response.headers.get("x-request-id") ?? requestId);
      if (!response.ok || !payload) return providerFailure(response, payload, requestId);
      raw = modelText(payload);
      try { parsed = raw ? parseJsonSafely(raw) : null; } catch (_) { parsed = null; }
    }

    if (!parsed) {
      const finishReason = String(payload?.candidates?.[0]?.finishReason ?? "");
      console.error("Vet AI Gemini invalid structured output", requestId, finishReason, raw?.length ?? 0, payload?.usageMetadata ?? {});
      return fail("GEMINI_INVALID_RESPONSE", ar ? "Gemini لم يُرجع نتيجة منظمة كاملة. تم تسجيل السبب." : "Gemini did not return a complete structured result.", 502, { provider_request_id: requestId, finish_reason: finishReason });
    }

    const m = parsed;
    const allowed = new Map(diseases.map((d: any) => [d.slug, d]));
    const differentials = (Array.isArray(m.differentials) ? m.differentials : [])
      .filter((d: any) => allowed.has(String(d?.catalog_slug ?? "")))
      .slice(0, 6)
      .map((d: any) => {
        const c: any = allowed.get(String(d.catalog_slug));
        return {
          catalog_slug: c.slug,
          name: clean(d.display_name || c.display_name),
          suspicion: ["low", "moderate", "high"].includes(d.suspicion) ? d.suspicion : "low",
          reasoning: clean(d.reasoning),
          cause: clean(c.cause),
          default_risk: c.default_risk,
          zoonotic: c.zoonotic,
          reportable_or_listed: c.reportable_or_listed,
          lab_confirmation_required: c.lab_confirmation_required,
          diagnostics_required: Boolean(c.lab_confirmation_required),
          prevention_summary: clean(c.prevention_summary),
          treatment_summary: clean(c.treatment_summary),
          owner_actions_summary: clean(c.owner_actions_summary),
          clinical_red_flags: cleanList(c.clinical_red_flags),
          isolation_guidance: clean(c.isolation_guidance),
        };
      });

    const groupMatch = ["match", "mismatch", "uncertain"].includes(m.group_match) ? m.group_match : "uncertain";
    const validRisk = ["none", "yellow", "orange", "red", "insufficient_data"].includes(m.risk) ? m.risk : "insufficient_data";
    const result = {
      code: groupMatch === "mismatch" ? "SPECIES_GROUP_MISMATCH" : "AI_ANALYSIS_COMPLETE",
      assessment_id: assessmentId,
      animal_group: animalGroup,
      group_match: groupMatch,
      image_quality: ["insufficient", "limited", "adequate"].includes(m.image_quality) ? m.image_quality : "limited",
      species_observed: clean(m.species_observed),
      summary: clean(groupMatch === "mismatch" ? (m.group_match_reason || m.summary) : m.summary),
      observed_signs: groupMatch === "mismatch" ? [] : cleanList(m.observed_signs).slice(0, 12),
      differential_diagnoses: groupMatch === "mismatch" ? [] : differentials,
      risk: groupMatch === "mismatch" ? "insufficient_data" : validRisk,
      urgent_vet_review: groupMatch === "mismatch" ? false : m.urgent_vet_review === true,
      isolation_recommended: groupMatch === "mismatch" ? false : m.isolation_recommended === true,
      lab_confirmation_required: groupMatch === "mismatch" ? false : m.lab_confirmation_required === true,
      immediate_actions: groupMatch === "mismatch" ? [] : cleanList(m.immediate_actions).slice(0, 8),
      follow_up_questions: groupMatch === "mismatch" ? [] : cleanList(m.follow_up_questions).slice(0, 6),
      confidence_statement: clean(m.confidence_statement),
      report_stage: "triage",
      provider: "gemini",
      model: MODEL,
      provider_request_id: requestId,
      generated_at: new Date().toISOString(),
    };

    const { error: saveError } = await supabase.from("assessments").update({
      observed_signs: result.observed_signs,
      differential_diagnoses: result.differential_diagnoses,
      risk: result.risk,
      isolation_recommended: result.isolation_recommended,
      urgent_vet_review: result.urgent_vet_review,
      lab_confirmation_required: result.lab_confirmation_required,
      status: "ai_review",
      ai_analysis: result,
      ai_model: MODEL,
      ai_provider_request_id: requestId || null,
      ai_usage: payload.usageMetadata ?? {},
      ai_generated_at: result.generated_at,
    }).eq("id", assessmentId);
    if (saveError) return fail("AI_RESULT_SAVE_FAILED", ar ? "تم إنشاء التحليل لكن تعذر حفظه بأمان." : "Analysis was generated but could not be saved.", 500);

    await supabase.from("alerts").delete().eq("assessment_id", assessmentId);
    if (result.risk === "red" || result.risk === "orange") {
      await supabase.from("alerts").insert({
        farm_id: assessment.farm_id,
        assessment_id: assessmentId,
        risk: result.risk,
        title: ar
          ? (result.risk === "red" ? "تنبيه صحي عاجل من Vet AI" : "حالة محتاجة مراجعة بيطرية")
          : (result.risk === "red" ? "Urgent Vet AI health alert" : "Vet AI veterinary review alert"),
        details: result.summary,
      });
    }

    return json(result);
  } catch (e) {
    console.error("analyze-case-unhandled", e);
    return fail("ANALYSIS_INTERNAL_ERROR", "The analysis service hit an internal error. Please retry.", 500);
  }
});