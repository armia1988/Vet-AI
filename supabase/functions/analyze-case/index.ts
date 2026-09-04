import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const GEMINI_MODEL = Deno.env.get("VET_AI_GEMINI_ANALYSIS_MODEL") ?? "gemini-2.5-flash";
const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8" },
});
const operational = (code: string, message: string, extra: Record<string, unknown> = {}, status = 200) =>
  json({ code, risk: "insufficient_data", message, ...extra }, status);
const mimeFromPath = (path: string) => {
  const ext = path.split(".").pop()?.toLowerCase();
  if (ext === "jpg" || ext === "jpeg") return "image/jpeg";
  if (ext === "png") return "image/png";
  if (ext === "webp") return "image/webp";
  if (ext === "gif") return "image/gif";
  return null;
};
const bytesToBase64 = (bytes: Uint8Array) => {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, Math.min(i + chunk, bytes.length)));
  }
  return btoa(binary);
};
const geminiText = (payload: any): string | null => {
  for (const candidate of payload?.candidates ?? []) {
    for (const part of candidate?.content?.parts ?? []) {
      if (typeof part?.text === "string" && part.text.trim()) return part.text.trim();
    }
  }
  return null;
};
const riskRank: Record<string, number> = { insufficient_data: -1, none: 0, yellow: 1, orange: 2, red: 3 };
const maxRisk = (a: string, b: string) => (riskRank[a] ?? -1) >= (riskRank[b] ?? -1) ? a : b;
const cleanText = (value: unknown) => String(value ?? "")
  .replace(/https?:\/\/\S+/gi, "")
  .replace(/\bwww\.\S+/gi, "")
  .replace(/\b(?:[a-z0-9-]+\.)+(?:com|org|gov|int|eu|edu|nl|uk)\b\S*/gi, "")
  .replace(/\s{2,}/g, " ")
  .trim();
const cleanArray = (value: unknown) => Array.isArray(value) ? value.map(cleanText).filter(Boolean) : [];

const triageSchema = {
  type: "OBJECT",
  properties: {
    image_quality: { type: "STRING", enum: ["insufficient", "limited", "adequate"] },
    group_match: { type: "STRING", enum: ["match", "mismatch", "uncertain"] },
    group_match_reason: { type: "STRING" },
    species_observed: { type: "STRING" },
    summary: { type: "STRING" },
    observed_signs: { type: "ARRAY", items: { type: "STRING" } },
    differentials: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          catalog_slug: { type: "STRING" },
          display_name: { type: "STRING" },
          suspicion: { type: "STRING", enum: ["low", "moderate", "high"] },
          reasoning: { type: "STRING" },
          cause_user: { type: "STRING" },
          treatment_user: { type: "STRING" },
          prevention_user: { type: "STRING" },
          owner_actions_user: { type: "STRING" },
        },
        required: ["catalog_slug", "display_name", "suspicion", "reasoning", "cause_user", "treatment_user", "prevention_user", "owner_actions_user"],
      },
    },
    risk: { type: "STRING", enum: ["none", "yellow", "orange", "red", "insufficient_data"] },
    urgent_vet_review: { type: "BOOLEAN" },
    isolation_recommended: { type: "BOOLEAN" },
    lab_confirmation_required: { type: "BOOLEAN" },
    immediate_actions: { type: "ARRAY", items: { type: "STRING" } },
    follow_up_questions: { type: "ARRAY", items: { type: "STRING" } },
    confidence_statement: { type: "STRING" },
  },
  required: [
    "image_quality", "group_match", "group_match_reason", "species_observed", "summary",
    "observed_signs", "differentials", "risk", "urgent_vet_review", "isolation_recommended",
    "lab_confirmation_required", "immediate_actions", "follow_up_questions", "confidence_statement",
  ],
};

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
    const auth = req.headers.get("Authorization");
    if (!auth) return json({ error: "Missing authorization" }, 401);

    const body = await req.json().catch(() => ({}));
    const assessmentId = typeof body?.assessment_id === "string" ? body.assessment_id : "";
    const requestedLanguage = typeof body?.language === "string" && /^[a-zA-Z-]{2,12}$/.test(body.language)
      ? body.language.toLowerCase()
      : "en";
    if (!assessmentId) return json({ error: "assessment_id is required" }, 400);

    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!geminiKey) {
      return operational(
        "GEMINI_NOT_CONFIGURED",
        requestedLanguage.startsWith("ar") ? "مفتاح Gemini غير متاح لخدمة التحليل." : "Gemini is not configured for the analysis service.",
        {},
        503,
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

    const { data: assessment, error: assessmentError } = await supabase
      .from("assessments")
      .select("id,farm_id,media_path,symptom_notes,status,risk,animal_group")
      .eq("id", assessmentId)
      .single();
    if (assessmentError || !assessment) return json({ error: "Assessment not found or access denied" }, 404);
    if (!assessment.media_path) return json({ error: "Assessment has no image" }, 400);
    const animalGroup = assessment.animal_group ?? "livestock";

    const { data: diseaseRows, error: diseaseError } = await supabase
      .from("disease_catalog")
      .select("id,slug,display_name,animal_groups,agent_type,cause,condition_type,body_systems,species_scope,preclinical_notes,diagnostics_summary,prevention_summary,epidemiology_summary,treatment_summary,owner_actions_summary,clinical_red_flags,jurisdiction_note,default_risk,isolation_guidance,lab_confirmation_required,reportable_or_listed,zoonotic,source_org,source_url,source_reviewed_at,curation_status")
      .eq("curation_status", "reviewed")
      .order("display_name");
    if (diseaseError || !diseaseRows) {
      return operational("KNOWLEDGE_BASE_UNAVAILABLE", requestedLanguage.startsWith("ar") ? "قاعدة المعرفة البيطرية غير متاحة مؤقتًا." : "The reviewed veterinary knowledge base is temporarily unavailable.");
    }
    const diseases = diseaseRows.filter((d: any) => Array.isArray(d.animal_groups) && d.animal_groups.includes(animalGroup));
    if (!diseases.length) {
      return operational("KNOWLEDGE_GAP", requestedLanguage.startsWith("ar") ? "لا توجد معرفة بيطرية مراجعة كافية للنوع المختار حتى الآن." : "No reviewed veterinary knowledge is available for the selected animal group yet.");
    }

    const ids = diseases.map((d: any) => d.id);
    const { data: signRows, error: signError } = await supabase
      .from("disease_signs")
      .select("disease_id,phase,sign,visible_in_image,visible_in_video,sensor_detectable")
      .in("disease_id", ids);
    if (signError) return operational("KNOWLEDGE_BASE_UNAVAILABLE", "The reviewed veterinary sign library is temporarily unavailable.");

    const catalogContext = diseases.map((d: any) => ({
      slug: d.slug,
      name: d.display_name,
      condition_type: d.condition_type,
      agent_type: d.agent_type,
      cause: d.cause,
      body_systems: d.body_systems,
      species_scope: d.species_scope,
      preclinical_notes: d.preclinical_notes,
      diagnostics_summary: d.diagnostics_summary,
      prevention_summary: d.prevention_summary,
      treatment_summary: d.treatment_summary,
      owner_actions_summary: d.owner_actions_summary,
      clinical_red_flags: d.clinical_red_flags,
      jurisdiction_note: d.jurisdiction_note,
      epidemiology_summary: d.epidemiology_summary,
      default_risk: d.default_risk,
      reportable_or_listed: d.reportable_or_listed,
      zoonotic: d.zoonotic,
      isolation_guidance: d.isolation_guidance,
      lab_confirmation_required: d.lab_confirmation_required,
      source_org: d.source_org,
      source_reviewed_at: d.source_reviewed_at,
      signs: (signRows ?? []).filter((s: any) => s.disease_id === d.id).map((s: any) => ({
        phase: s.phase,
        sign: s.sign,
        visible_in_image: s.visible_in_image,
        sensor_detectable: s.sensor_detectable,
      })),
    }));

    const { data: mediaBlob, error: mediaError } = await supabase.storage.from("diagnostic-media").download(assessment.media_path);
    if (mediaError || !mediaBlob) return json({ error: "Image unavailable or access denied" }, 404);
    if (mediaBlob.size > MAX_IMAGE_BYTES) {
      return operational("IMAGE_TOO_LARGE", requestedLanguage.startsWith("ar") ? "حجم الصورة كبير جدًا للتحليل. اختر صورة أوضح وأصغر." : "The image is too large for analysis. Choose a smaller clear image.");
    }
    const mime = mimeFromPath(assessment.media_path);
    if (!mime) return operational("UNSUPPORTED_IMAGE_FORMAT", "Use JPEG, PNG, WEBP or GIF for AI analysis.");
    const imageBase64 = bytesToBase64(new Uint8Array(await mediaBlob.arrayBuffer()));
    const validSlugs = new Set(diseases.map((d: any) => d.slug));

    const languageRule = requestedLanguage.startsWith("ar")
      ? "Write EVERY user-facing field in clear professional Egyptian Arabic. Do not mix English explanatory sentences into Arabic. Use familiar Egyptian wording while keeping veterinary terminology accurate. Scientific Latin names may appear only when useful. Never include URLs or bibliography text in user-facing fields."
      : `Write every user-facing field naturally in language code ${requestedLanguage}. Do not mix another language into explanatory text. Never include URLs in user-facing fields.`;

    const systemPrompt = `You are the fast first-pass veterinary decision-support inference layer for Vet AI. This is high-stakes animal-health triage, not an autonomous veterinarian.\n\n${languageRule}\n\nRules:\n1. Verify image compatibility with the selected animal group first. A human, unrelated object, or clearly different animal group must return mismatch and no disease guess.\n2. Never make a definitive diagnosis from one image. Separate visible findings, history and differential possibilities.\n3. Name only catalog_slug values present in the supplied reviewed catalog. If the pattern does not fit, return no differential rather than forcing one.\n4. Never invent confidence percentages; use low/moderate/high suspicion only.\n5. Red is reserved for credible critical/high-consequence patterns, not merely because one listed disease is dangerous.\n6. For cattle skin lesions, distinguish superficial annular/scaly/alopecic/crusted lesions from deep firm dermal nodules. Do not assign high suspicion for lumpy skin disease from circular superficial alopecic crusted plaques alone. High LSD suspicion normally requires a compatible nodule pattern plus systemic or epidemiological support such as fever, enlarged superficial lymph nodes, oedema, marked milk drop, widespread characteristic firm nodules, or a known outbreak/exposure. If circular scaly alopecic gray/white crusted plaques dominate without systemic signs, dermatophytosis/ringworm should rank ahead of LSD when present in the catalog. Also consider dermatophilosis, papillomatosis, mange and photosensitization when their pattern fits.\n7. Reportable, zoonotic or high-consequence patterns require conservative biosecurity and veterinary/laboratory confirmation.\n8. Do not provide drug doses or prescription regimens. Owner-safe topical/external management may be summarized only when supported by the reviewed catalog.\n9. Localize disease display names and user guidance instead of copying English catalog prose into a different-language UI.\n10. Keep the first-pass report concise and ask only discriminating follow-up questions.`;

    const userPrompt = `Selected animal group: ${animalGroup}\nUser symptoms/history notes: ${assessment.symptom_notes?.trim() || "No symptom notes supplied."}\n\nReviewed veterinary knowledge:\n${JSON.stringify(catalogContext)}\n\nPerform a fast first-pass image triage. Return visible findings, reviewed-catalog differentials, risk, immediate safety actions and the smallest useful set of follow-up questions needed before a final report.`;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);
    let providerResponse: Response;
    try {
      providerResponse = await fetch(`${GEMINI_BASE}/${encodeURIComponent(GEMINI_MODEL)}:generateContent`, {
        method: "POST",
        signal: controller.signal,
        headers: {
          "x-goog-api-key": geminiKey,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: systemPrompt }] },
          contents: [{
            role: "user",
            parts: [
              { text: userPrompt },
              { inline_data: { mime_type: mime, data: imageBase64 } },
            ],
          }],
          generationConfig: {
            temperature: 0.15,
            maxOutputTokens: 1600,
            responseMimeType: "application/json",
            responseSchema: triageSchema,
          },
        }),
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === "AbortError") {
        return operational("GEMINI_TIMEOUT", requestedLanguage.startsWith("ar") ? "تحليل Gemini أخذ وقتًا أطول من المتوقع. جرّب مرة أخرى بصورة واضحة." : "Gemini analysis took longer than expected. Retry with a clear image.");
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }

    const providerPayload = await providerResponse.json().catch(() => null);
    const providerRequestId = String(providerPayload?.responseId ?? providerResponse.headers.get("x-request-id") ?? "");
    if (!providerResponse.ok || !providerPayload) {
      const statusName = String(providerPayload?.error?.status ?? "");
      const providerMessage = String(providerPayload?.error?.message ?? "");
      console.error("Vet AI Gemini error", providerResponse.status, statusName, providerRequestId, providerMessage);
      if (providerResponse.status === 401 || providerResponse.status === 403 || statusName === "PERMISSION_DENIED" || statusName === "UNAUTHENTICATED") {
        return operational("GEMINI_AUTH_ERROR", requestedLanguage.startsWith("ar") ? "Gemini رفض مفتاح الـAPI أو الصلاحية الخاصة به." : "Gemini rejected the API key or its permissions.", { provider_request_id: providerRequestId }, 502);
      }
      if (providerResponse.status === 429 || statusName === "RESOURCE_EXHAUSTED") {
        return operational("GEMINI_RATE_LIMIT", requestedLanguage.startsWith("ar") ? "Gemini وصل لحد استخدام مؤقت على حساب الـAPI. ده مش معناه إن رصيدك خلص. حاول بعد وقت قصير." : "Gemini reached a temporary API account limit. This does not necessarily mean the account balance is exhausted. Retry shortly.", { provider_request_id: providerRequestId }, 429);
      }
      if (providerResponse.status === 400 || statusName === "INVALID_ARGUMENT") {
        return operational("GEMINI_REQUEST_ERROR", requestedLanguage.startsWith("ar") ? "Gemini رفض إعدادات طلب التحليل. تم تسجيل الخطأ للمراجعة." : "Gemini rejected the analysis request configuration.", { provider_request_id: providerRequestId }, 502);
      }
      return operational("GEMINI_PROVIDER_ERROR", requestedLanguage.startsWith("ar") ? "Gemini لم يتمكن من إكمال التحليل الآن." : "Gemini could not complete the analysis.", { provider_request_id: providerRequestId, provider_status: providerResponse.status }, 502);
    }

    const rawText = geminiText(providerPayload);
    if (!rawText) return operational("GEMINI_EMPTY_RESPONSE", "Gemini returned no usable assessment text.", { provider_request_id: providerRequestId }, 502);

    let modelResult: any;
    try {
      modelResult = JSON.parse(rawText);
    } catch {
      return operational("GEMINI_INVALID_RESPONSE", requestedLanguage.startsWith("ar") ? "Gemini أعاد نتيجة غير صالحة للعرض الآمن." : "Gemini returned a response that did not match the safety schema.", { provider_request_id: providerRequestId }, 502);
    }

    if (modelResult.group_match === "mismatch") {
      const mismatchResult = {
        code: "SPECIES_GROUP_MISMATCH",
        assessment_id: assessmentId,
        animal_group: animalGroup,
        image_quality: modelResult.image_quality,
        species_observed: cleanText(modelResult.species_observed),
        summary: cleanText(modelResult.group_match_reason || modelResult.summary),
        observed_signs: [],
        differential_diagnoses: [],
        risk: "insufficient_data",
        urgent_vet_review: false,
        isolation_recommended: false,
        lab_confirmation_required: false,
        immediate_actions: [],
        follow_up_questions: [],
        confidence_statement: cleanText(modelResult.confidence_statement),
        report_stage: "triage",
        model: GEMINI_MODEL,
        provider: "gemini",
        provider_request_id: providerRequestId,
        generated_at: new Date().toISOString(),
      };
      await supabase.from("assessments").update({
        observed_signs: [],
        differential_diagnoses: [],
        risk: "insufficient_data",
        isolation_recommended: false,
        urgent_vet_review: false,
        lab_confirmation_required: false,
        status: "ai_review",
        ai_analysis: mismatchResult,
        ai_model: GEMINI_MODEL,
        ai_provider_request_id: providerRequestId || null,
        ai_usage: providerPayload.usageMetadata ?? {},
        ai_generated_at: mismatchResult.generated_at,
      }).eq("id", assessmentId);
      return json(mismatchResult);
    }

    const enrichedDifferentials = (Array.isArray(modelResult.differentials) ? modelResult.differentials : [])
      .filter((d: any) => validSlugs.has(d.catalog_slug))
      .slice(0, 6)
      .map((d: any) => {
        const catalog = diseases.find((x: any) => x.slug === d.catalog_slug)!;
        return {
          catalog_slug: catalog.slug,
          name: cleanText(d.display_name || catalog.display_name),
          condition_type: catalog.condition_type,
          suspicion: d.suspicion,
          reasoning: cleanText(d.reasoning),
          cause: cleanText(d.cause_user),
          default_risk: catalog.default_risk,
          zoonotic: catalog.zoonotic,
          reportable_or_listed: catalog.reportable_or_listed,
          lab_confirmation_required: catalog.lab_confirmation_required,
          diagnostics_required: Boolean(catalog.lab_confirmation_required),
          prevention_summary: cleanText(d.prevention_user),
          treatment_summary: cleanText(d.treatment_user),
          owner_actions_summary: cleanText(d.owner_actions_user),
          clinical_red_flags: cleanArray(catalog.clinical_red_flags),
          jurisdiction_note: cleanText(catalog.jurisdiction_note),
          source_org: cleanText(catalog.source_org),
          isolation_guidance: cleanText(catalog.isolation_guidance),
        };
      });

    let finalRisk = String(modelResult.risk ?? "insufficient_data");
    if (!(finalRisk in riskRank)) finalRisk = "insufficient_data";
    if (modelResult.urgent_vet_review === true) finalRisk = maxRisk(finalRisk, "orange");
    for (const d of enrichedDifferentials) {
      if (d.suspicion === "high" && d.default_risk === "red") finalRisk = "red";
      else if (d.suspicion === "moderate" && d.default_risk === "red") finalRisk = maxRisk(finalRisk, "orange");
      else if (d.suspicion === "high" && d.default_risk === "orange") finalRisk = maxRisk(finalRisk, "orange");
    }
    if ((modelResult.group_match === "uncertain" || modelResult.image_quality === "insufficient") && !assessment.symptom_notes?.trim() && enrichedDifferentials.length === 0) {
      finalRisk = "insufficient_data";
    }

    const isolationRecommended = modelResult.isolation_recommended === true || enrichedDifferentials.some((d: any) =>
      (d.suspicion === "moderate" || d.suspicion === "high") && Boolean(d.isolation_guidance));
    const labRequired = modelResult.lab_confirmation_required === true || enrichedDifferentials.some((d: any) =>
      (d.suspicion === "moderate" || d.suspicion === "high") && d.lab_confirmation_required === true);

    const result = {
      code: "AI_ANALYSIS_COMPLETE",
      assessment_id: assessmentId,
      animal_group: animalGroup,
      group_match: modelResult.group_match,
      image_quality: modelResult.image_quality,
      species_observed: cleanText(modelResult.species_observed),
      summary: cleanText(modelResult.summary),
      observed_signs: cleanArray(modelResult.observed_signs).slice(0, 12),
      differential_diagnoses: enrichedDifferentials,
      risk: finalRisk,
      urgent_vet_review: modelResult.urgent_vet_review === true,
      isolation_recommended: isolationRecommended,
      lab_confirmation_required: labRequired,
      immediate_actions: cleanArray(modelResult.immediate_actions).slice(0, 8),
      follow_up_questions: cleanArray(modelResult.follow_up_questions).slice(0, 6),
      confidence_statement: cleanText(modelResult.confidence_statement),
      report_stage: "triage",
      model: GEMINI_MODEL,
      provider: "gemini",
      provider_request_id: providerRequestId,
      generated_at: new Date().toISOString(),
    };

    const { error: updateError } = await supabase.from("assessments").update({
      observed_signs: result.observed_signs,
      differential_diagnoses: result.differential_diagnoses,
      risk: result.risk,
      isolation_recommended: result.isolation_recommended,
      urgent_vet_review: result.urgent_vet_review,
      lab_confirmation_required: result.lab_confirmation_required,
      status: "ai_review",
      ai_analysis: result,
      ai_model: GEMINI_MODEL,
      ai_provider_request_id: providerRequestId || null,
      ai_usage: providerPayload.usageMetadata ?? {},
      ai_generated_at: result.generated_at,
    }).eq("id", assessmentId);
    if (updateError) return operational("AI_RESULT_SAVE_FAILED", "The assessment was generated but could not be saved safely.", {}, 500);

    await supabase.from("alerts").delete().eq("assessment_id", assessmentId);
    if (result.risk === "red" || result.risk === "orange") {
      const title = requestedLanguage.startsWith("ar")
        ? (result.risk === "red" ? "تنبيه صحي عاجل من Vet AI" : "حالة محتاجة مراجعة بيطرية")
        : (result.risk === "red" ? "Urgent Vet AI health alert" : "Vet AI veterinary review alert");
      await supabase.from("alerts").insert({
        farm_id: assessment.farm_id,
        assessment_id: assessmentId,
        risk: result.risk,
        title,
        details: result.summary,
      });
    }

    return json(result);
  } catch (error) {
    console.error("analyze-case-unhandled", error);
    return operational("ANALYSIS_INTERNAL_ERROR", "The analysis service hit an internal error. Please retry.", {}, 500);
  }
});