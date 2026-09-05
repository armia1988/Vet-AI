import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_MODEL") ?? "gemini-3.6-flash";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});
const fail = (code: string, message: string, status = 200, extra: Record<string, unknown> = {}) =>
  json({ code, risk: "insufficient_data", message, ...extra }, status);
const text = (v: unknown) => String(v ?? "").replace(/https?:\/\/\S+/gi, "").replace(/\s{2,}/g, " ").trim();
const arr = (v: unknown) => Array.isArray(v) ? v.map(text).filter(Boolean) : [];
const mimeFromPath = (path: string) => {
  const ext = path.split(".").pop()?.toLowerCase();
  if (ext === "jpg" || ext === "jpeg") return "image/jpeg";
  if (ext === "png") return "image/png";
  if (ext === "webp") return "image/webp";
  return null;
};
const bytesToBase64 = (bytes: Uint8Array) => {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, Math.min(i + 0x8000, bytes.length)));
  return btoa(s);
};
const modelText = (payload: any) => {
  for (const c of payload?.candidates ?? []) for (const p of c?.content?.parts ?? []) if (typeof p?.text === "string" && p.text.trim()) return p.text.trim();
  return null;
};
const parseJson = (raw: string) => {
  const cleaned = raw.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  return JSON.parse(cleaned);
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
    if (diseaseError || !allDiseases) return fail("KNOWLEDGE_BASE_UNAVAILABLE", ar ? "قاعدة المعرفة البيطرية غير متاحة مؤقتًا." : "Veterinary knowledge base is temporarily unavailable.");
    const diseases = allDiseases.filter((d: any) => Array.isArray(d.animal_groups) && d.animal_groups.includes(animalGroup));
    if (!diseases.length) return fail("KNOWLEDGE_GAP", ar ? "لا توجد معرفة بيطرية مراجعة كافية للنوع المختار." : "No reviewed veterinary knowledge is available for this animal group.");

    const ids = diseases.map((d: any) => d.id);
    const { data: signs } = await supabase
      .from("disease_signs")
      .select("disease_id,phase,sign,visible_in_image,sensor_detectable")
      .in("disease_id", ids);

    const catalog = diseases.map((d: any) => ({
      slug: d.slug,
      name: d.display_name,
      cause: d.cause,
      default_risk: d.default_risk,
      treatment: d.treatment_summary,
      prevention: d.prevention_summary,
      owner_actions: d.owner_actions_summary,
      red_flags: d.clinical_red_flags,
      isolation: d.isolation_guidance,
      lab_confirmation_required: d.lab_confirmation_required,
      zoonotic: d.zoonotic,
      reportable_or_listed: d.reportable_or_listed,
      signs: (signs ?? []).filter((s: any) => s.disease_id === d.id).map((s: any) => ({ phase: s.phase, sign: s.sign, visible_in_image: s.visible_in_image })),
    }));

    const { data: blob, error: mediaError } = await supabase.storage.from("diagnostic-media").download(assessment.media_path);
    if (mediaError || !blob) return json({ error: "Image unavailable or access denied" }, 404);
    if (blob.size > MAX_IMAGE_BYTES) return fail("IMAGE_TOO_LARGE", ar ? "الصورة كبيرة جدًا للتحليل." : "Image is too large for analysis.");
    const mime = mimeFromPath(assessment.media_path);
    if (!mime) return fail("UNSUPPORTED_IMAGE_FORMAT", ar ? "استخدم صورة JPEG أو PNG أو WEBP." : "Use JPEG, PNG or WEBP.");
    const image = bytesToBase64(new Uint8Array(await blob.arrayBuffer()));

    const languageInstruction = ar
      ? "اكتب كل الحقول التي يراها المستخدم بالعربية المصرية الواضحة والمهنية، بدون خلط جمل إنجليزية."
      : `Write every user-facing field naturally in language code ${language}.`;
    const prompt = `You are Vet AI, a veterinary decision-support triage system. You are NOT a substitute for a veterinarian. ${languageInstruction}\n\nSelected animal group: ${animalGroup}\nSymptoms/history: ${assessment.symptom_notes?.trim() || "None supplied"}\n\nReviewed disease catalog (ONLY these slugs may be returned):\n${JSON.stringify(catalog)}\n\nAnalyze the image conservatively. First verify that the image matches the selected animal group. Never claim a definitive diagnosis from one image. Prefer visible findings and differential possibilities. High-consequence diseases require compatible visible/systemic evidence and veterinary/laboratory confirmation. Do not provide prescription doses.\n\nReturn ONLY valid JSON with exactly these keys:\n{\n  "image_quality":"insufficient|limited|adequate",\n  "group_match":"match|mismatch|uncertain",\n  "group_match_reason":"string",\n  "species_observed":"string",\n  "summary":"string",\n  "observed_signs":["string"],\n  "differentials":[{"catalog_slug":"string","display_name":"string","suspicion":"low|moderate|high","reasoning":"string"}],\n  "risk":"none|yellow|orange|red|insufficient_data",\n  "urgent_vet_review":false,\n  "isolation_recommended":false,\n  "lab_confirmation_required":false,\n  "immediate_actions":["string"],\n  "follow_up_questions":["string"],\n  "confidence_statement":"string"\n}`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 45000);
    let response: Response;
    try {
      response = await fetch(`${BASE}/${encodeURIComponent(MODEL)}:generateContent`, {
        method: "POST",
        signal: controller.signal,
        headers: { "x-goog-api-key": key, "content-type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }, { inline_data: { mime_type: mime, data: image } }] }],
          generationConfig: { temperature: 0.1, maxOutputTokens: 2200, responseMimeType: "application/json" },
        }),
      });
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") return fail("GEMINI_TIMEOUT", ar ? "Gemini أخذ وقتًا أطول من المتوقع. جرّب مرة أخرى." : "Gemini took longer than expected. Please retry.", 504);
      throw e;
    } finally {
      clearTimeout(timer);
    }

    const payload = await response.json().catch(() => null);
    const requestId = String(payload?.responseId ?? response.headers.get("x-request-id") ?? "");
    if (!response.ok || !payload) {
      const providerStatus = String(payload?.error?.status ?? "");
      const providerMessage = String(payload?.error?.message ?? "");
      console.error("Vet AI Gemini provider error", response.status, providerStatus, requestId, providerMessage);
      if (response.status === 401 || response.status === 403 || providerStatus === "PERMISSION_DENIED" || providerStatus === "UNAUTHENTICATED")
        return fail("GEMINI_AUTH_ERROR", ar ? "Gemini رفض مفتاح الـAPI أو صلاحياته." : "Gemini rejected the API key or permissions.", 502, { provider_request_id: requestId });
      if (response.status === 404 || providerStatus === "NOT_FOUND")
        return fail("GEMINI_MODEL_UNAVAILABLE", ar ? "نموذج Gemini المحدد غير متاح للحساب. تم تسجيل المشكلة." : "The configured Gemini model is unavailable for this account.", 502, { provider_request_id: requestId });
      if (response.status === 429 || providerStatus === "RESOURCE_EXHAUSTED")
        return fail("GEMINI_RATE_LIMIT", ar ? "Gemini وصل لحد استخدام مؤقت. حاول بعد وقت قصير." : "Gemini reached a temporary usage limit.", 429, { provider_request_id: requestId });
      return fail("GEMINI_PROVIDER_ERROR", ar ? "Gemini لم يتمكن من إكمال التحليل الآن." : "Gemini could not complete the analysis.", 502, { provider_request_id: requestId, provider_status: response.status });
    }

    const raw = modelText(payload);
    if (!raw) return fail("GEMINI_EMPTY_RESPONSE", ar ? "Gemini لم يُرجع نتيجة قابلة للعرض." : "Gemini returned no usable result.", 502, { provider_request_id: requestId });
    let m: any;
    try { m = parseJson(raw); } catch { return fail("GEMINI_INVALID_RESPONSE", ar ? "Gemini أعاد نتيجة غير صالحة للعرض الآمن." : "Gemini returned invalid structured output.", 502, { provider_request_id: requestId }); }

    const allowed = new Map(diseases.map((d: any) => [d.slug, d]));
    const differentials = (Array.isArray(m.differentials) ? m.differentials : [])
      .filter((d: any) => allowed.has(String(d?.catalog_slug ?? "")))
      .slice(0, 6)
      .map((d: any) => {
        const c: any = allowed.get(String(d.catalog_slug));
        return {
          catalog_slug: c.slug,
          name: text(d.display_name || c.display_name),
          suspicion: ["low", "moderate", "high"].includes(d.suspicion) ? d.suspicion : "low",
          reasoning: text(d.reasoning),
          cause: text(c.cause),
          default_risk: c.default_risk,
          zoonotic: c.zoonotic,
          reportable_or_listed: c.reportable_or_listed,
          lab_confirmation_required: c.lab_confirmation_required,
          diagnostics_required: Boolean(c.lab_confirmation_required),
          prevention_summary: text(c.prevention_summary),
          treatment_summary: text(c.treatment_summary),
          owner_actions_summary: text(c.owner_actions_summary),
          clinical_red_flags: arr(c.clinical_red_flags),
          isolation_guidance: text(c.isolation_guidance),
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
      species_observed: text(m.species_observed),
      summary: text(groupMatch === "mismatch" ? (m.group_match_reason || m.summary) : m.summary),
      observed_signs: groupMatch === "mismatch" ? [] : arr(m.observed_signs).slice(0, 12),
      differential_diagnoses: groupMatch === "mismatch" ? [] : differentials,
      risk: groupMatch === "mismatch" ? "insufficient_data" : validRisk,
      urgent_vet_review: groupMatch === "mismatch" ? false : m.urgent_vet_review === true,
      isolation_recommended: groupMatch === "mismatch" ? false : m.isolation_recommended === true,
      lab_confirmation_required: groupMatch === "mismatch" ? false : m.lab_confirmation_required === true,
      immediate_actions: groupMatch === "mismatch" ? [] : arr(m.immediate_actions).slice(0, 8),
      follow_up_questions: groupMatch === "mismatch" ? [] : arr(m.follow_up_questions).slice(0, 6),
      confidence_statement: text(m.confidence_statement),
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
        title: ar ? (result.risk === "red" ? "تنبيه صحي عاجل من Vet AI" : "حالة محتاجة مراجعة بيطرية") : (result.risk === "red" ? "Urgent Vet AI health alert" : "Vet AI veterinary review alert"),
        details: result.summary,
      });
    }
    return json(result);
  } catch (e) {
    console.error("analyze-case-unhandled", e);
    return fail("ANALYSIS_INTERNAL_ERROR", "The analysis service hit an internal error. Please retry.", 500);
  }
});