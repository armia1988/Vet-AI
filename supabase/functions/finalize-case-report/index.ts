import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = "gemini-3.6-flash";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const REPORT_FORMAT_VERSION = 2;

const FINAL_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    report_title: { type: "string" },
    primary_condition: {
      type: "object",
      additionalProperties: false,
      properties: {
        catalog_slug: { type: "string" },
        name: { type: "string" },
        suspicion: { type: "string", enum: ["low", "moderate", "high", "uncertain"] },
        why: { type: "string" },
      },
      required: ["catalog_slug", "name", "suspicion", "why"],
    },
    risk: { type: "string", enum: ["none", "yellow", "orange", "red", "insufficient_data"] },
    risk_reason: { type: "string" },
    summary: { type: "string" },
    cause: { type: "string" },
    vet_required: { type: "string", enum: ["now", "today", "soon", "not_routinely"] },
    vet_required_reason: { type: "string" },
    topical_or_external_care: { type: "array", maxItems: 5, items: { type: "string" } },
    treatment_and_management: { type: "array", maxItems: 8, items: { type: "string" } },
    prevention: { type: "array", maxItems: 8, items: { type: "string" } },
    what_to_do_now: { type: "array", maxItems: 8, items: { type: "string" } },
    veterinary_next_steps: { type: "array", maxItems: 8, items: { type: "string" } },
    red_flags: { type: "array", maxItems: 8, items: { type: "string" } },
    confirmation_plan: { type: "array", maxItems: 8, items: { type: "string" } },
    follow_up_summary: { type: "array", maxItems: 14, items: { type: "string" } },
    food_animal_medicine_note: { type: "string" },
    voice_summary: { type: "string" },
    confidence_statement: { type: "string" },
  },
  required: [
    "report_title", "primary_condition", "risk", "risk_reason", "summary", "cause", "vet_required",
    "vet_required_reason", "topical_or_external_care", "treatment_and_management", "prevention",
    "what_to_do_now", "veterinary_next_steps", "red_flags", "confirmation_plan", "follow_up_summary",
    "food_animal_medicine_note", "voice_summary", "confidence_statement"
  ],
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

const clean = (value: unknown) => String(value ?? "")
  .replace(/https?:\/\/\S+/gi, "")
  .replace(/\bwww\.\S+/gi, "")
  .replace(/\s{2,}/g, " ")
  .trim();

const modelText = (payload: any): string | null => {
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
  try { return JSON.parse(value); } catch (_) {}
  const first = value.indexOf("{");
  const last = value.lastIndexOf("}");
  if (first >= 0 && last > first) return JSON.parse(value.slice(first, last + 1));
  throw new Error("No complete JSON object in Gemini response");
};

async function sha(text: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

const isArabic = (language: string) => language.startsWith("ar");
const providerError = (ar: boolean, code: string, status = 502) => json({
  code,
  risk: "insufficient_data",
  ...(ar ? { message: "تعذر إنشاء التقرير بنفس لغة الهاتف الآن. جرّب مرة أخرى." } : {}),
}, status);

const arabicEnglishLeak = (value: unknown) => {
  const text = JSON.stringify(value ?? {});
  return /\b(the|and|with|reduce|optimize|diagnosis|treatment|prevention|cause|host|environment|respiratory|management|clinical|testing|disease)\b/i.test(text);
};

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
    const auth = req.headers.get("Authorization");
    if (!auth) return json({ error: "Missing authorization" }, 401);

    const body = await req.json().catch(() => ({}));
    const assessmentId = typeof body?.assessment_id === "string" ? body.assessment_id : "";
    const language = typeof body?.language === "string" && /^[a-zA-Z-]{2,12}$/.test(body.language)
      ? body.language.toLowerCase()
      : "en";
    const ar = isArabic(language);
    const answers = Array.isArray(body?.answers) ? body.answers.slice(0, 14) : [];
    if (!assessmentId) return json({ error: "assessment_id is required" }, 400);

    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) return providerError(ar, "GEMINI_NOT_CONFIGURED", 503);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

    const { data: assessment, error: assessmentError } = await supabase.from("assessments")
      .select("id,farm_id,animal_group,symptom_notes,ai_analysis,ai_usage,risk,status")
      .eq("id", assessmentId)
      .single();
    if (assessmentError || !assessment) return json({ error: "Assessment not found or access denied" }, 404);

    const cleanAnswers: Array<{ question: string; answer: string }> = [];
    for (const row of answers) {
      const question = typeof row?.question === "string" ? row.question.trim().slice(0, 800) : "";
      const answer = typeof row?.answer === "string" ? row.answer.trim().slice(0, 1200) : "";
      if (question && answer) cleanAnswers.push({ question, answer });
    }
    const fingerprint = await sha(JSON.stringify(cleanAnswers));

    if (
      assessment.status === "final_report" &&
      assessment.ai_analysis?.code === "FINAL_REPORT_COMPLETE" &&
      assessment.ai_usage?.follow_up_fingerprint === fingerprint &&
      assessment.ai_usage?.report_language === language &&
      assessment.ai_usage?.report_format_version === REPORT_FORMAT_VERSION
    ) {
      return json(assessment.ai_analysis);
    }

    const initial = assessment.ai_analysis && typeof assessment.ai_analysis === "object" ? assessment.ai_analysis : {};
    const diffs = Array.isArray(initial?.differential_diagnoses) ? initial.differential_diagnoses.slice(0, 6) : [];
    const slugs = diffs.map((d: any) => d?.catalog_slug).filter((x: any) => typeof x === "string" && x);

    let catalog: any[] = [];
    if (slugs.length) {
      const { data } = await supabase.from("disease_catalog")
        .select("slug,display_name,cause,condition_type,diagnostics_summary,prevention_summary,treatment_summary,owner_actions_summary,clinical_red_flags,jurisdiction_note,default_risk,isolation_guidance,lab_confirmation_required,reportable_or_listed,zoonotic,source_org,source_url,source_reviewed_at")
        .in("slug", slugs)
        .eq("curation_status", "reviewed");
      catalog = data ?? [];
    }

    if (cleanAnswers.length) {
      await supabase.from("assessment_followups").insert(cleanAnswers.map((x) => ({
        assessment_id: assessmentId,
        user_id: userData.user.id,
        question: x.question,
        answer: x.answer,
      })));
    }

    const localeRule = ar
      ? "كل نص يراه المستخدم يجب أن يكون بالعربية المصرية المهنية الواضحة فقط. ترجم أي نص إنجليزي في قاعدة المعرفة إلى العربية. ممنوع خلط جمل إنجليزية داخل التقرير. أسماء الكائنات العلمية اللاتينية فقط يمكن إبقاؤها عند الضرورة الطبية."
      : `Every user-facing string must be naturally written in language code ${language}. Translate all catalog prose into that language. Never mix explanatory English sentences into a non-English report. Latin scientific organism names may remain only when medically necessary.`;

    const systemPrompt = `You are Vet AI. Produce a FINAL veterinary decision-support report from the reviewed internal knowledge below. ${localeRule}\nSafety rules: one image never proves a diagnosis; reassess the differentials using follow-up answers; never invent prescription doses, injection schedules or withdrawal periods; clearly state whether and when a veterinarian is required; for food animals preserve medication/withdrawal safety. Return only the requested JSON structure.`;
    const input = `Target language: ${language}\nAnimal group: ${assessment.animal_group ?? "unknown"}\nSymptoms/history: ${assessment.symptom_notes ?? ""}\nInitial triage: ${JSON.stringify({ summary: initial?.summary, risk: initial?.risk, observed_signs: initial?.observed_signs, differential_diagnoses: diffs })}\nFollow-up answers: ${JSON.stringify(cleanAnswers)}\nReviewed catalog: ${JSON.stringify(catalog)}\nBuild the final report now.`;

    const callGemini = async (prompt: string, maxOutputTokens = 7000) => {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 40000);
      try {
        const response = await fetch(`${BASE}/${MODEL}:generateContent`, {
          method: "POST",
          signal: controller.signal,
          headers: { "x-goog-api-key": key, "content-type": "application/json" },
          body: JSON.stringify({
            systemInstruction: { parts: [{ text: systemPrompt }] },
            contents: [{ role: "user", parts: [{ text: prompt }] }],
            generationConfig: {
              temperature: 0.1,
              maxOutputTokens,
              thinkingConfig: { thinkingLevel: "low" },
              responseMimeType: "application/json",
              responseJsonSchema: FINAL_SCHEMA,
            },
          }),
        });
        const payload = await response.json().catch(() => null);
        return { response, payload };
      } finally {
        clearTimeout(timer);
      }
    };

    let response: Response;
    let payload: any;
    try {
      ({ response, payload } = await callGemini(input));
    } catch (e) {
      if (e instanceof DOMException && e.name === "AbortError") return providerError(ar, "GEMINI_TIMEOUT", 504);
      throw e;
    }

    const requestId = String(payload?.responseId ?? response.headers.get("x-request-id") ?? "");
    if (!response.ok || !payload) {
      console.error("finalize-case-report Gemini error", response.status, payload?.error?.status ?? "", requestId, String(payload?.error?.message ?? "").slice(0, 500));
      if (response.status === 429 || payload?.error?.status === "RESOURCE_EXHAUSTED") return providerError(ar, "GEMINI_RATE_LIMIT", 429);
      if (response.status === 401 || response.status === 403) return providerError(ar, "GEMINI_AUTH_ERROR", 502);
      if (response.status === 404) return providerError(ar, "GEMINI_MODEL_UNAVAILABLE", 502);
      return providerError(ar, "GEMINI_PROVIDER_ERROR", 502);
    }

    let raw = modelText(payload);
    let parsed: any;
    try {
      if (!raw) throw new Error("empty response");
      parsed = parseJson(raw);
    } catch (e) {
      console.error("finalize-case-report invalid JSON", requestId, String(e), raw?.slice(0, 400) ?? "");
      return providerError(ar, "GEMINI_INVALID_RESPONSE", 502);
    }

    if (ar && arabicEnglishLeak(parsed)) {
      const repairPrompt = `The JSON below contains English prose but the target report language is Arabic. Translate every user-facing string value into clear professional Egyptian Arabic. Preserve JSON keys, catalog_slug values, risk/vet_required/suspicion enum values, and medically necessary Latin scientific names. Return the same JSON schema with no explanatory English sentences.\nJSON: ${JSON.stringify(parsed)}`;
      try {
        const repaired = await callGemini(repairPrompt, 7000);
        if (repaired.response.ok && repaired.payload) {
          const repairedRaw = modelText(repaired.payload);
          if (repairedRaw) parsed = parseJson(repairedRaw);
        }
      } catch (e) {
        console.warn("final report localization repair failed", String(e));
      }
      if (arabicEnglishLeak(parsed)) {
        console.error("final report still contains English prose after repair", requestId);
        return providerError(true, "FINAL_REPORT_LANGUAGE_MIX", 502);
      }
    }

    const evidenceRows = catalog.filter((x: any) => x?.source_org && x?.source_url && x?.source_reviewed_at);
    const finalResult = {
      code: "FINAL_REPORT_COMPLETE",
      report_stage: "final",
      assessment_id: assessmentId,
      ...parsed,
      evidence_verified: evidenceRows.length > 0,
      source_labels: [...new Set(evidenceRows.map((x: any) => clean(x.source_org)).filter(Boolean))].slice(0, 8),
      provider: "gemini",
      model: MODEL,
      provider_request_id: requestId || null,
      fast_fallback: false,
      report_language: language,
      generated_at: new Date().toISOString(),
    };

    const usage = {
      ...(payload?.usageMetadata ?? {}),
      follow_up_fingerprint: fingerprint,
      report_language: language,
      report_format_version: REPORT_FORMAT_VERSION,
      mode: "gemini_structured_localized",
      provider: "gemini",
    };

    const { error: saveError } = await supabase.from("assessments").update({
      risk: finalResult.risk,
      status: "final_report",
      ai_analysis: finalResult,
      ai_model: MODEL,
      ai_provider_request_id: requestId || null,
      ai_usage: usage,
      ai_generated_at: finalResult.generated_at,
    }).eq("id", assessmentId);
    if (saveError) return json({ code: "FINAL_REPORT_SAVE_FAILED", risk: "insufficient_data" }, 500);

    await supabase.from("alerts").delete().eq("assessment_id", assessmentId);
    if (finalResult.risk === "red" || finalResult.risk === "orange") {
      await supabase.from("alerts").insert({
        farm_id: assessment.farm_id,
        assessment_id: assessmentId,
        risk: finalResult.risk,
        title: ar
          ? (finalResult.risk === "red" ? "تنبيه صحي عاجل من Vet AI" : "حالة محتاجة مراجعة بيطرية")
          : (finalResult.risk === "red" ? "Urgent Vet AI health alert" : "Vet AI veterinary review alert"),
        details: finalResult.summary,
      });
    }

    return json(finalResult);
  } catch (e) {
    console.error("finalize-case-report-unhandled", e);
    return json({ code: "FINAL_REPORT_INTERNAL_ERROR", risk: "insufficient_data" }, 500);
  }
});