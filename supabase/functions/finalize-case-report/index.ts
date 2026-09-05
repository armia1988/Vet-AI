import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const PRIMARY_MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_MODEL") ?? "gemini-3.6-flash";
const FALLBACK_MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_FALLBACK_MODEL") ?? "gemini-3.5-flash-lite";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const REPORT_FORMAT_VERSION = 3;

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
const list = (value: unknown) => Array.isArray(value) ? value.map(clean).filter(Boolean) : [];
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
const languageText = (language: string, en: string, ar: string, nl: string) =>
  isArabic(language) ? ar : language.startsWith("nl") ? nl : en;
const arabicEnglishLeak = (value: unknown) => {
  const text = JSON.stringify(value ?? {});
  return /\b(the|and|with|reduce|optimize|diagnosis|treatment|prevention|cause|environment|respiratory|management|clinical|testing|disease)\b/i.test(text);
};
const validRisk = (value: unknown) => ["none", "yellow", "orange", "red", "insufficient_data"].includes(String(value))
  ? String(value)
  : "insufficient_data";
const vetNeed = (risk: string) => risk === "red" ? "now" : risk === "orange" ? "today" : risk === "yellow" ? "soon" : "not_routinely";

function safeFallback(
  language: string,
  assessmentId: string,
  initial: any,
  catalog: any[],
  answers: Array<{ question: string; answer: string }>,
) {
  const diffs = Array.isArray(initial?.differential_diagnoses) ? initial.differential_diagnoses : [];
  const top = diffs[0] ?? {};
  const risk = validRisk(initial?.risk);
  const need = vetNeed(risk);
  const name = clean(top?.name || languageText(language, "Unconfirmed veterinary condition", "حالة بيطرية غير مؤكدة", "Niet-bevestigde veterinaire aandoening"));
  const summary = clean(initial?.summary) || languageText(
    language,
    "The available image and case answers support a cautious veterinary follow-up, but they do not prove a diagnosis.",
    "الصورة وإجابات الحالة تسمح بمتابعة بيطرية حذرة، لكنها لا تثبت تشخيصًا نهائيًا.",
    "De beschikbare foto en antwoorden ondersteunen een voorzichtige veterinaire follow-up, maar bewijzen geen diagnose.",
  );
  const why = clean(top?.reasoning) || languageText(
    language,
    "This is the closest reviewed possibility from the available case data; veterinary confirmation may still be required.",
    "ده أقرب احتمال من البيانات المتاحة والمعرفة المراجعة، ولسه ممكن يحتاج تأكيد من طبيب بيطري.",
    "Dit is de best passende beoordeelde mogelijkheid op basis van de beschikbare gegevens; veterinaire bevestiging kan nog nodig zijn.",
  );
  const vetReason = risk === "red"
    ? languageText(language, "The current risk pattern needs immediate veterinary assessment.", "مستوى الخطورة الحالي محتاج تقييم بيطري فوري.", "Het huidige risicopatroon vereist directe veterinaire beoordeling.")
    : risk === "orange"
      ? languageText(language, "Arrange a veterinary assessment today.", "رتّب كشف بيطري النهارده.", "Regel vandaag een veterinaire beoordeling.")
      : risk === "yellow"
        ? languageText(language, "Arrange veterinary review soon if signs persist, spread or worsen.", "رتّب مراجعة بيطرية قريب لو العلامات استمرت أو انتشرت أو زادت.", "Regel binnenkort veterinaire controle als klachten aanhouden, uitbreiden of erger worden.")
        : languageText(language, "Seek veterinary help if the animal deteriorates or new concerning signs appear.", "اطلب مساعدة بيطرية لو الحالة ساءت أو ظهرت علامات مقلقة جديدة.", "Zoek veterinaire hulp als het dier achteruitgaat of nieuwe zorgwekkende klachten krijgt.");
  const actions = list(initial?.immediate_actions);
  const evidenceRows = catalog.filter((x: any) => x?.source_org && x?.source_url && x?.source_reviewed_at);
  return {
    code: "FINAL_REPORT_COMPLETE",
    report_stage: "final",
    assessment_id: assessmentId,
    report_title: languageText(language, "Vet AI final veterinary report", "تقرير Vet AI البيطري النهائي", "Definitief veterinair Vet AI-rapport"),
    primary_condition: {
      catalog_slug: clean(top?.catalog_slug || "unconfirmed"),
      name,
      suspicion: ["low", "moderate", "high", "uncertain"].includes(String(top?.suspicion)) ? String(top.suspicion) : "uncertain",
      why,
    },
    risk,
    risk_reason: clean(initial?.confidence_statement) || vetReason,
    summary,
    cause: languageText(
      language,
      "The exact cause cannot be confirmed from the image alone and may require clinical examination or targeted testing.",
      "السبب الدقيق ماينفعش يتأكد من الصورة لوحدها، وممكن يحتاج كشف سريري أو فحوصات موجهة.",
      "De exacte oorzaak kan niet op basis van alleen de foto worden bevestigd en kan klinisch onderzoek of gerichte tests vereisen.",
    ),
    vet_required: need,
    vet_required_reason: vetReason,
    topical_or_external_care: [],
    treatment_and_management: [
      languageText(language, "Keep the animal comfortable, reduce avoidable stress and use only veterinary products approved for this animal and location.", "خلي الحيوان مرتاح وقلل الإجهاد غير الضروري، وما تستخدمش غير منتجات بيطرية معتمدة للحيوان وفي بلدك.", "Houd het dier comfortabel, beperk onnodige stress en gebruik alleen goedgekeurde diergeneesmiddelen voor dit dier en deze locatie."),
      languageText(language, "Do not invent or guess prescription doses, injection schedules or withdrawal periods.", "ما تخمّنش جرعات أدوية أو مواعيد حقن أو فترات سحب اللبن واللحوم.", "Raad geen receptdoseringen, injectieschema's of wachttijden voor melk/vlees."),
    ],
    prevention: [
      languageText(language, "Improve hygiene and reduce contact with other animals when infection is plausible.", "حسّن النظافة وقلل اختلاط الحيوان بباقي الحيوانات لو العدوى احتمال وارد.", "Verbeter hygiëne en beperk contact met andere dieren wanneer infectie mogelijk is."),
      languageText(language, "Monitor other animals for similar changes and record any progression.", "راقب باقي الحيوانات لنفس العلامات وسجّل أي تطور في الحالة.", "Controleer andere dieren op vergelijkbare veranderingen en leg het verloop vast."),
    ],
    what_to_do_now: actions.length ? actions : [
      languageText(language, "Photograph changes, record appetite, behavior and temperature if available, and keep the case history up to date.", "صوّر أي تغيرات، وسجّل الشهية والسلوك والحرارة لو متاحة، وحدّث تاريخ الحالة.", "Fotografeer veranderingen, noteer eetlust, gedrag en temperatuur indien beschikbaar en houd de voorgeschiedenis actueel."),
    ],
    veterinary_next_steps: [
      languageText(language, "A veterinarian can decide whether direct examination, sampling or laboratory confirmation is needed.", "الطبيب البيطري يحدد هل محتاج كشف مباشر أو عينة أو تأكيد معملي.", "Een dierenarts kan bepalen of direct onderzoek, bemonstering of laboratoriumbevestiging nodig is."),
    ],
    red_flags: [
      languageText(language, "Severe breathing difficulty, collapse, inability to stand, uncontrolled bleeding or rapid deterioration require urgent veterinary help.", "صعوبة تنفس شديدة، انهيار، عدم القدرة على الوقوف، نزيف غير متحكم فيه أو تدهور سريع محتاجين طبيب بيطري فورًا.", "Ernstige benauwdheid, instorten, niet kunnen staan, ongecontroleerde bloeding of snelle achteruitgang vereisen spoedzorg."),
    ],
    confirmation_plan: [
      languageText(language, "Clinical examination and targeted tests based on the veterinarian's findings.", "كشف سريري وفحوصات موجهة حسب نتيجة فحص الطبيب البيطري.", "Klinisch onderzoek en gerichte tests op basis van de bevindingen van de dierenarts."),
    ],
    follow_up_summary: answers.map((x) => `${clean(x.question)}: ${clean(x.answer)}`).slice(0, 14),
    food_animal_medicine_note: languageText(
      language,
      "For food-producing animals, medicines must follow local approval and meat/milk withdrawal requirements. Vet AI does not invent prescription doses or withdrawal periods.",
      "في حيوانات إنتاج الغذاء، أي دواء لازم يلتزم بالاعتماد المحلي وفترات سحب اللبن واللحوم. Vet AI ما بيخترعش جرعات أو فترات سحب.",
      "Voor voedselproducerende dieren moeten geneesmiddelen voldoen aan lokale toelating en wachttijden voor vlees/melk. Vet AI verzint geen doseringen of wachttijden.",
    ),
    voice_summary: `${name}. ${summary} ${vetReason}`,
    confidence_statement: languageText(
      language,
      "This is veterinary decision support based on the case data and reviewed Vet AI knowledge, not a laboratory-confirmed diagnosis.",
      "ده دعم قرار بيطري مبني على بيانات الحالة ومعرفة Vet AI المراجعة، ومش تشخيص مؤكد معمليًا.",
      "Dit is veterinaire beslissingsondersteuning op basis van de casus en beoordeelde Vet AI-kennis, geen laboratoriumbevestigde diagnose.",
    ),
    evidence_verified: evidenceRows.length > 0,
    source_labels: [...new Set(evidenceRows.map((x: any) => clean(x.source_org)).filter(Boolean))].slice(0, 8),
    provider: "reviewed-catalog-fallback",
    model: "reviewed-catalog-fallback",
    fast_fallback: true,
    report_language: language,
    generated_at: new Date().toISOString(),
  };
}

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
      const { error: followupError } = await supabase.from("assessment_followups").insert(cleanAnswers.map((x) => ({
        assessment_id: assessmentId,
        user_id: userData.user.id,
        question: x.question,
        answer: x.answer,
      })));
      if (followupError) console.error("assessment follow-up save failed", followupError.message);
    }

    const fallback = safeFallback(language, assessmentId, initial, catalog, cleanAnswers);
    const key = Deno.env.get("GEMINI_API_KEY");
    let finalResult: any = fallback;
    let usage: any = {
      follow_up_fingerprint: fingerprint,
      report_language: language,
      report_format_version: REPORT_FORMAT_VERSION,
      mode: "reviewed_catalog_fallback",
      provider: "reviewed_catalog",
    };

    if (key && catalog.length) {
      const localeRule = ar
        ? "كل نص يراه المستخدم لازم يكون بالعربية المصرية المهنية والواضحة فقط. ترجم أي نص إنجليزي من قاعدة المعرفة للعربية. ممنوع خلط جمل إنجليزية في التقرير. أسماء الكائنات العلمية اللاتينية فقط ممكن تفضل كما هي عند الضرورة الطبية."
        : `Every user-facing string must be naturally written in language code ${language}. Translate catalog prose into that language and do not mix explanatory English sentences into a non-English report.`;
      const systemPrompt = `You are Vet AI. Produce a FINAL veterinary decision-support report from the reviewed internal knowledge below. ${localeRule}\nSafety: one image never proves a diagnosis; reassess using the follow-up answers; never invent prescription doses, injection schedules or withdrawal periods; clearly state whether and when a veterinarian is required; preserve food-animal medicine safety. Return only the requested JSON structure.`;
      const input = `Target language: ${language}\nAnimal group: ${assessment.animal_group ?? "unknown"}\nSymptoms/history: ${assessment.symptom_notes ?? ""}\nInitial triage: ${JSON.stringify({ summary: initial?.summary, risk: initial?.risk, observed_signs: initial?.observed_signs, differential_diagnoses: diffs })}\nFollow-up answers: ${JSON.stringify(cleanAnswers)}\nReviewed catalog: ${JSON.stringify(catalog)}\nBuild the final report now.`;

      const callGemini = async (model: string, timeoutMs: number) => {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), timeoutMs);
        try {
          const response = await fetch(`${BASE}/${encodeURIComponent(model)}:generateContent`, {
            method: "POST",
            signal: controller.signal,
            headers: { "x-goog-api-key": key, "content-type": "application/json" },
            body: JSON.stringify({
              systemInstruction: { parts: [{ text: systemPrompt }] },
              contents: [{ role: "user", parts: [{ text: input }] }],
              generationConfig: {
                temperature: 0.1,
                maxOutputTokens: 5200,
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

      const attempts = [
        { model: PRIMARY_MODEL, timeoutMs: 22000 },
        { model: FALLBACK_MODEL, timeoutMs: 16000 },
      ].filter((a, index, rows) => rows.findIndex((x) => x.model === a.model) === index);
      const failures: string[] = [];

      for (const attempt of attempts) {
        try {
          const { response, payload } = await callGemini(attempt.model, attempt.timeoutMs);
          const requestId = String(payload?.responseId ?? response.headers.get("x-request-id") ?? "");
          if (!response.ok || !payload) {
            console.warn("finalize-case-report attempt failed", attempt.model, response.status, payload?.error?.status ?? "", requestId);
            failures.push(`${attempt.model}:${response.status || payload?.error?.status || "provider_error"}`);
            continue;
          }
          const raw = modelText(payload);
          let parsed: any = null;
          try { parsed = raw ? parseJson(raw) : null; } catch (_) { parsed = null; }
          if (!parsed || (ar && arabicEnglishLeak(parsed))) {
            failures.push(`${attempt.model}:${parsed ? "language_mix" : "invalid_json"}`);
            continue;
          }
          const evidenceRows = catalog.filter((x: any) => x?.source_org && x?.source_url && x?.source_reviewed_at);
          finalResult = {
            code: "FINAL_REPORT_COMPLETE",
            report_stage: "final",
            assessment_id: assessmentId,
            ...parsed,
            evidence_verified: evidenceRows.length > 0,
            source_labels: [...new Set(evidenceRows.map((x: any) => clean(x.source_org)).filter(Boolean))].slice(0, 8),
            provider: "gemini",
            model: attempt.model,
            provider_request_id: requestId || null,
            fast_fallback: false,
            report_language: language,
            generated_at: new Date().toISOString(),
          };
          usage = {
            ...(payload?.usageMetadata ?? {}),
            follow_up_fingerprint: fingerprint,
            report_language: language,
            report_format_version: REPORT_FORMAT_VERSION,
            mode: "gemini_structured_localized",
            provider: "gemini",
            model: attempt.model,
            failover_used: attempt.model !== PRIMARY_MODEL,
            failed_attempts: failures,
          };
          break;
        } catch (error) {
          const timeout = error instanceof DOMException && error.name === "AbortError";
          failures.push(`${attempt.model}:${timeout ? "timeout" : "exception"}`);
          console.warn("finalize-case-report attempt exception", attempt.model, timeout ? "timeout" : String(error));
        }
      }

      if (finalResult.fast_fallback === true) {
        usage = { ...usage, failed_attempts: failures };
      }
    }

    const { error: saveError } = await supabase.from("assessments").update({
      risk: finalResult.risk,
      status: "final_report",
      ai_analysis: finalResult,
      ai_model: finalResult.model,
      ai_provider_request_id: finalResult.provider_request_id ?? null,
      ai_usage: usage,
      ai_generated_at: finalResult.generated_at,
    }).eq("id", assessmentId);
    if (saveError) return json({ code: "FINAL_REPORT_SAVE_FAILED", risk: "insufficient_data", message: ar ? "تم إنشاء التقرير لكن تعذر حفظه بأمان." : "The final report was generated but could not be saved." }, 500);

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
  } catch (error) {
    console.error("finalize-case-report unhandled", error);
    return json({ code: "FINAL_REPORT_INTERNAL_ERROR", risk: "insufficient_data", message: "The final report service hit an internal error." }, 500);
  }
});
