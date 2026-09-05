import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_MODEL") ?? "gemini-3.5-flash-lite";
const FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_FALLBACK_MODEL") ?? "gemini-3.6-flash";
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
      maxItems: 4,
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
    immediate_actions: { type: "array", maxItems: 5, items: { type: "string" } },
    follow_up_questions: { type: "array", maxItems: 4, items: { type: "string" } },
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
const sha256Hex = async (bytes: Uint8Array) => {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", copy.buffer);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
};
const sha256Text = (value: string) => sha256Hex(new TextEncoder().encode(value));
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
    if (!key) return fail("GEMINI_NOT_CONFIGURED", ar ? "خدمة الذكاء البيطري غير مهيأة حاليًا." : "The veterinary AI service is not configured.", 503);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: authData, error: authError } = await supabase.auth.getUser();
    if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

    const { data: assessment, error: assessmentError } = await supabase
      .from("assessments")
      .select("id,farm_id,media_path,symptom_notes,animal_group,ai_analysis,ai_model,ai_provider_request_id,ai_usage,ai_generated_at,status")
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
      return fail("KNOWLEDGE_BASE_UNAVAILABLE", ar ? "قاعدة المعرفة البيطرية غير متاحة مؤقتًا." : "Veterinary knowledge is temporarily unavailable.", 503);
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
    const imageBytes = new Uint8Array(await blob.arrayBuffer());
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

    const languageInstruction = ar
      ? "اكتب كل الحقول التي يراها المستخدم بالعربية المصرية الواضحة والمهنية فقط، من غير خلط جمل إنجليزية."
      : `Write every user-facing field naturally in language code ${language}.`;
    const prompt = `You are Vet AI, a veterinary decision-support triage system. ${languageInstruction}\nSelected animal group: ${animalGroup}\nSymptoms/history: ${assessment.symptom_notes?.trim() || "None supplied"}\nReviewed disease catalog. ONLY these catalog_slug values may be returned:\n${JSON.stringify(modelCatalog)}\nAnalyze the image conservatively. Verify the animal group first. Never claim a definitive diagnosis from one image. Only report signs actually visible. Rank differentials ONLY by compatibility with visible signs plus supplied history. Do not choose a disease just because it is common. If evidence is weak or two conditions are similarly plausible, keep suspicion low/moderate and state uncertainty instead of arbitrarily switching the top disease. Return no more than four differentials. High-consequence diseases require compatible evidence and veterinary/laboratory confirmation. Never invent medication doses or withdrawal periods.`;

    const callGemini = async (model: string, timeoutMs: number) => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), timeoutMs);
      try {
        const response = await fetch(`${BASE}/${encodeURIComponent(model)}:generateContent`, {
          method: "POST",
          signal: controller.signal,
          headers: { "x-goog-api-key": key, "content-type": "application/json" },
          body: JSON.stringify({
            contents: [{ role: "user", parts: [{ text: prompt }, { inline_data: { mime_type: mime, data: image } }] }],
            generationConfig: {
              candidateCount: 1,
              seed: parseInt(inputFingerprint.slice(0, 8), 16) & 0x7fffffff,
              maxOutputTokens: 2200,
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

    const attempts = [
      { model: PRIMARY_MODEL, timeoutMs: 9500 },
      { model: FALLBACK_MODEL, timeoutMs: 10500 },
    ].filter((a, index, rows) => rows.findIndex((x) => x.model === a.model) === index);

    let parsed: any = null;
    let payload: any = null;
    let requestId = "";
    let usedModel = "";
    const failures: string[] = [];

    for (const attempt of attempts) {
      try {
        const result = await callGemini(attempt.model, attempt.timeoutMs);
        const response = result.response;
        payload = result.payload;
        requestId = String(payload?.responseId ?? response.headers.get("x-request-id") ?? requestId);
        const providerStatus = String(payload?.error?.status ?? "");
        if (!response.ok || !payload) {
          console.error("Vet AI Gemini attempt failed", attempt.model, response.status, providerStatus, requestId, String(payload?.error?.message ?? "").slice(0, 400));
          if (response.status === 401 || response.status === 403 || providerStatus === "PERMISSION_DENIED" || providerStatus === "UNAUTHENTICATED") {
            return fail("GEMINI_AUTH_ERROR", ar ? "خدمة التحليل رفضت صلاحيات المزود." : "The AI provider rejected its credentials.", 502, { provider_request_id: requestId });
          }
          failures.push(`${attempt.model}:${response.status || providerStatus || "provider_error"}`);
          continue;
        }

        const finishReason = String(payload?.candidates?.[0]?.finishReason ?? "");
        if (["SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT"].includes(finishReason) || payload?.promptFeedback?.blockReason) {
          return fail("GEMINI_SAFETY_STOP", ar ? "تم إيقاف التحليل بسبب فلتر أمان. استخدم صورة واضحة للحيوان فقط." : "The analysis was stopped by a safety filter.", 422, { provider_request_id: requestId });
        }

        const raw = modelText(payload);
        try {
          parsed = raw ? parseJsonSafely(raw) : null;
        } catch (_) {
          parsed = null;
        }
        if (parsed && finishReason !== "MAX_TOKENS") {
          usedModel = attempt.model;
          break;
        }
        console.warn("Vet AI Gemini structured attempt incomplete", attempt.model, requestId, finishReason, raw?.length ?? 0);
        failures.push(`${attempt.model}:${finishReason || "invalid_json"}`);
        parsed = null;
      } catch (error) {
        const isTimeout = error instanceof DOMException && error.name === "AbortError";
        console.warn("Vet AI Gemini attempt exception", attempt.model, isTimeout ? "timeout" : String(error));
        failures.push(`${attempt.model}:${isTimeout ? "timeout" : "exception"}`);
      }
    }

    if (!parsed || !usedModel) {
      return fail(
        "GEMINI_TEMPORARILY_UNAVAILABLE",
        ar
          ? "تعذر إكمال التحليل بعد المحاولة الأساسية والاحتياطية. حاول مرة أخرى بعد قليل."
          : "The analysis could not be completed after the primary and fallback attempts. Please retry shortly.",
        503,
        { provider_request_id: requestId || null, attempts: failures },
      );
    }

    const m = parsed;
    const allowed = new Map(diseases.map((d: any) => [d.slug, d]));
    const differentials = (Array.isArray(m.differentials) ? m.differentials : [])
      .filter((d: any) => allowed.has(String(d?.catalog_slug ?? "")))
      .slice(0, 4)
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
      })
      .sort((a: any, b: any) => {
        const rank: Record<string, number> = { high: 3, moderate: 2, low: 1 };
        const delta = (rank[b.suspicion] ?? 0) - (rank[a.suspicion] ?? 0);
        return delta || String(a.catalog_slug).localeCompare(String(b.catalog_slug));
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
      model: usedModel,
      provider_request_id: requestId || null,
      failover_used: usedModel !== PRIMARY_MODEL,
      input_fingerprint: inputFingerprint,
      image_sha256: imageSha256,
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
      ai_model: usedModel,
      ai_provider_request_id: requestId || null,
      ai_usage: { ...(payload?.usageMetadata ?? {}), failover_used: usedModel !== PRIMARY_MODEL, attempts: failures },
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
  } catch (error) {
    console.error("analyze-case-unhandled", error);
    return fail("ANALYSIS_INTERNAL_ERROR", "The analysis service hit an internal error. Please retry.", 500);
  }
});
