import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_MODEL") ?? "gemini-2.5-flash";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json; charset=utf-8" } });
const geminiText = (payload: any): string | null => {
  for (const candidate of payload?.candidates ?? []) {
    for (const part of candidate?.content?.parts ?? []) {
      if (typeof part?.text === "string" && part.text.trim()) return part.text.trim();
    }
  }
  return null;
};
const cleanText = (value: unknown) => String(value ?? "").replace(/https?:\/\/\S+/gi, "").replace(/\bwww\.\S+/gi, "").replace(/\s{2,}/g, " ").trim();
const splitGuidance = (value: unknown) => {
  const text = cleanText(value);
  if (!text) return [];
  return text.split(/(?:\n+|;\s+|\.\s+(?=[A-ZÀ-ÿ\u0600-\u06FF]))/).map((x) => x.trim()).filter(Boolean).slice(0, 7);
};
const riskRank: Record<string, number> = { insufficient_data: -1, none: 0, yellow: 1, orange: 2, red: 3 };
const safeRisk = (value: unknown) => String(value ?? "insufficient_data") in riskRank ? String(value) : "insufficient_data";
const vetNeed = (risk: string) => risk === "red" ? "now" : risk === "orange" ? "today" : risk === "yellow" ? "soon" : "not_routinely";
const isArabic = (language: string) => language.toLowerCase().startsWith("ar");
const localized = (language: string, en: string, ar: string) => isArabic(language) ? ar : en;

async function sha(text: string) {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function fallbackReport(language: string, assessmentId: string, initial: any, catalog: any[], answers: Array<{question:string,answer:string}>) {
  const diffs = Array.isArray(initial?.differential_diagnoses) ? initial.differential_diagnoses : [];
  const top = diffs[0] ?? {};
  const row = catalog.find((x: any) => x.slug === top?.catalog_slug) ?? catalog[0] ?? {};
  const name = cleanText(top?.name || row?.display_name || localized(language, "Unconfirmed veterinary condition", "حالة بيطرية غير مؤكدة"));
  const risk = safeRisk(initial?.risk);
  const treatment = splitGuidance(top?.treatment_summary || row?.treatment_summary);
  const prevention = splitGuidance(top?.prevention_summary || row?.prevention_summary);
  const actions = splitGuidance(top?.owner_actions_summary || row?.owner_actions_summary);
  const diagnostics = splitGuidance(row?.diagnostics_summary);
  const cause = cleanText(top?.cause || row?.cause || localized(language, "Cause requires confirmation.", "السبب محتاج تأكيد بيطري أو معملي."));
  const summary = cleanText(initial?.summary || localized(language, "The available image and answers support a cautious veterinary follow-up report, but they do not prove a diagnosis.", "الصورة والإجابات تسمح بتقرير متابعة بيطري حذر، لكنها لا تثبت التشخيص بشكل نهائي."));
  const evidenceRows = catalog.filter((x: any) => x?.source_org && x?.source_url && x?.source_reviewed_at);
  const labels = [...new Set(evidenceRows.map((x: any) => cleanText(x.source_org)).filter(Boolean))].slice(0, 8);
  const need = vetNeed(risk);
  const vetReason = risk === "red"
    ? localized(language, "The current risk level requires immediate veterinary assessment and appropriate biosecurity.", "مستوى الخطورة الحالي محتاج تقييم بيطري فوري مع إجراءات الأمان الحيوي المناسبة.")
    : risk === "orange"
      ? localized(language, "Arrange a veterinary assessment today because the pattern needs timely clinical confirmation.", "رتّب كشف بيطري النهارده لأن النمط محتاج تأكيد سريري في وقت مناسب.")
      : risk === "yellow"
        ? localized(language, "A veterinary review should be arranged soon if signs persist, spread or worsen.", "رتّب مراجعة بيطرية قريب لو العلامات استمرت أو انتشرت أو زادت.")
        : localized(language, "Routine veterinary review is not automatically required from the current evidence, but seek help if the animal deteriorates.", "المعطيات الحالية مش بتفرض كشف بيطري عاجل تلقائيًا، لكن اطلب المساعدة لو حالة الحيوان ساءت.");
  return {
    code: "FINAL_REPORT_COMPLETE",
    report_stage: "final",
    assessment_id: assessmentId,
    report_title: localized(language, "Vet AI final veterinary report", "تقرير Vet AI البيطري النهائي"),
    primary_condition: {
      catalog_slug: cleanText(top?.catalog_slug || row?.slug || "unconfirmed"),
      name,
      suspicion: ["low","moderate","high","uncertain"].includes(String(top?.suspicion)) ? String(top.suspicion) : "uncertain",
      why: cleanText(top?.reasoning || localized(language, "This is the best fit among the reviewed possibilities, but confirmation is still required.", "ده أقرب احتمال من الحالات المراجعة، لكن لسه محتاج تأكيد.")),
    },
    risk,
    risk_reason: cleanText(initial?.confidence_statement || vetReason),
    summary,
    cause,
    vet_required: need,
    vet_required_reason: vetReason,
    topical_or_external_care: treatment.filter((x: string) => /topical|external|wash|clean|hygiene|موضعي|خارجي|تنظيف|غسل/i.test(x)).slice(0, 4),
    treatment_and_management: treatment.length ? treatment : [localized(language, "Use only locally approved veterinary products and follow the veterinarian/product label for food animals.", "استخدم فقط منتجات بيطرية معتمدة محليًا، واتبع تعليمات الطبيب والملصق خصوصًا لحيوانات الغذاء.")],
    prevention: prevention.length ? prevention : [localized(language, "Reduce exposure, improve hygiene and monitor other animals for similar signs.", "قلل الاختلاط، حسّن النظافة، وراقب باقي الحيوانات لأي علامات مشابهة.")],
    what_to_do_now: actions.length ? actions : [localized(language, "Photograph progression, record temperature/behavior if available, and separate the affected animal when contagion is plausible.", "صوّر تطور الحالة، وسجّل الحرارة والسلوك لو متاح، وافصل الحيوان المصاب لو العدوى احتمال وارد.")],
    veterinary_next_steps: diagnostics.length ? diagnostics : [localized(language, "A veterinarian can decide whether examination, sampling or laboratory confirmation is needed.", "الطبيب البيطري يحدد هل محتاج فحص مباشر أو عينة أو تأكيد معملي.")],
    red_flags: splitGuidance(row?.clinical_red_flags),
    confirmation_plan: diagnostics.length ? diagnostics : [localized(language, "Clinical examination and targeted testing if the condition persists or risk increases.", "كشف سريري وفحوصات موجهة لو الحالة استمرت أو مستوى الخطورة زاد.")],
    follow_up_summary: answers.map((x) => `${cleanText(x.question)}: ${cleanText(x.answer)}`).slice(0, 12),
    food_animal_medicine_note: localized(language, "For food-producing animals, medicines must comply with local approval and meat/milk withdrawal requirements. Vet AI does not invent prescription doses or withdrawal periods.", "في حيوانات إنتاج الغذاء، أي دواء لازم يلتزم بالاعتماد المحلي وفترات سحب اللبن/اللحوم. Vet AI ما بيخترعش جرعات وصفية أو فترات سحب."),
    voice_summary: `${name}. ${summary} ${vetReason}`,
    confidence_statement: localized(language, "This report is decision support based on the case data and reviewed Vet AI knowledge. It is not a laboratory-confirmed diagnosis.", "التقرير ده دعم قرار مبني على بيانات الحالة ومعرفة Vet AI المراجعة، ومش تشخيص مؤكد معمليًا."),
    evidence_verified: evidenceRows.length > 0,
    source_labels: labels,
    provider: "catalog-fallback",
    model: "catalog-fallback",
    fast_fallback: true,
    generated_at: new Date().toISOString(),
  };
}

const finalSchema = {
  type: "OBJECT",
  properties: {
    report_title: { type: "STRING" },
    primary_condition: {
      type: "OBJECT",
      properties: {
        catalog_slug: { type: "STRING" },
        name: { type: "STRING" },
        suspicion: { type: "STRING", enum: ["low","moderate","high","uncertain"] },
        why: { type: "STRING" },
      },
      required: ["catalog_slug","name","suspicion","why"],
    },
    risk: { type: "STRING", enum: ["none","yellow","orange","red","insufficient_data"] },
    risk_reason: { type: "STRING" },
    summary: { type: "STRING" },
    cause: { type: "STRING" },
    vet_required: { type: "STRING", enum: ["now","today","soon","not_routinely"] },
    vet_required_reason: { type: "STRING" },
    topical_or_external_care: { type: "ARRAY", items: { type: "STRING" } },
    treatment_and_management: { type: "ARRAY", items: { type: "STRING" } },
    prevention: { type: "ARRAY", items: { type: "STRING" } },
    what_to_do_now: { type: "ARRAY", items: { type: "STRING" } },
    veterinary_next_steps: { type: "ARRAY", items: { type: "STRING" } },
    red_flags: { type: "ARRAY", items: { type: "STRING" } },
    confirmation_plan: { type: "ARRAY", items: { type: "STRING" } },
    follow_up_summary: { type: "ARRAY", items: { type: "STRING" } },
    food_animal_medicine_note: { type: "STRING" },
    voice_summary: { type: "STRING" },
    confidence_statement: { type: "STRING" },
  },
  required: ["report_title","primary_condition","risk","risk_reason","summary","cause","vet_required","vet_required_reason","topical_or_external_care","treatment_and_management","prevention","what_to_do_now","veterinary_next_steps","red_flags","confirmation_plan","follow_up_summary","food_animal_medicine_note","voice_summary","confidence_statement"],
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Missing authorization" }, 401);

  const body = await req.json().catch(() => ({}));
  const assessmentId = typeof body?.assessment_id === "string" ? body.assessment_id : "";
  const language = typeof body?.language === "string" && /^[a-zA-Z-]{2,12}$/.test(body.language) ? body.language.toLowerCase() : "en";
  const answers = Array.isArray(body?.answers) ? body.answers.slice(0, 14) : [];
  if (!assessmentId) return json({ error: "assessment_id is required" }, 400);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

  const { data: assessment, error: assessmentError } = await supabase.from("assessments")
    .select("id,farm_id,animal_group,symptom_notes,ai_analysis,ai_usage,risk,status")
    .eq("id", assessmentId).single();
  if (assessmentError || !assessment) return json({ error: "Assessment not found or access denied" }, 404);

  const cleanAnswers: Array<{question:string,answer:string}> = [];
  for (const row of answers) {
    const question = typeof row?.question === "string" ? row.question.trim().slice(0, 800) : "";
    const answer = typeof row?.answer === "string" ? row.answer.trim().slice(0, 1200) : "";
    if (question && answer) cleanAnswers.push({ question, answer });
  }
  const fingerprint = await sha(JSON.stringify(cleanAnswers));
  if (assessment.status === "final_report" && assessment.ai_analysis?.code === "FINAL_REPORT_COMPLETE" && assessment.ai_usage?.follow_up_fingerprint === fingerprint) {
    return json(assessment.ai_analysis);
  }

  const initial = assessment.ai_analysis && typeof assessment.ai_analysis === "object" ? assessment.ai_analysis : {};
  const diffs = Array.isArray(initial?.differential_diagnoses) ? initial.differential_diagnoses.slice(0, 6) : [];
  const slugs = diffs.map((d: any) => d?.catalog_slug).filter((x: any) => typeof x === "string" && x);
  let catalog: any[] = [];
  if (slugs.length) {
    const { data } = await supabase.from("disease_catalog")
      .select("slug,display_name,cause,condition_type,diagnostics_summary,prevention_summary,treatment_summary,owner_actions_summary,clinical_red_flags,jurisdiction_note,default_risk,isolation_guidance,lab_confirmation_required,reportable_or_listed,zoonotic,source_org,source_url,source_reviewed_at")
      .in("slug", slugs).eq("curation_status", "reviewed");
    catalog = data ?? [];
  }
  if (cleanAnswers.length) {
    await supabase.from("assessment_followups").insert(cleanAnswers.map((x) => ({ assessment_id: assessmentId, user_id: userData.user.id, question: x.question, answer: x.answer })));
  }

  const fallback = fallbackReport(language, assessmentId, initial, catalog, cleanAnswers);
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  let finalResult: any = fallback;
  let usage: any = { follow_up_fingerprint: fingerprint, mode: "catalog_fallback", provider: "catalog" };

  if (geminiKey && catalog.length) {
    const localeRule = isArabic(language)
      ? "Write every user-facing field in clear professional Egyptian Arabic. Do not mix English explanatory sentences into Arabic. Latin scientific organism names may appear only where medically useful."
      : `Write all user-facing fields naturally in language code ${language}.`;
    const systemPrompt = `You produce a fast FINAL veterinary decision-support report from an already-reviewed internal knowledge base. No web search is allowed. ${localeRule}\nRules: never claim one image proves a diagnosis; re-evaluate the top differential using the follow-up answers; keep medication guidance conservative; never invent prescription doses, injection schedules or withdrawal periods; state clearly whether a veterinarian is needed and when; preserve food-animal medicine safety; return only the requested JSON structure.`;
    const input = `Initial triage: ${JSON.stringify({summary: initial?.summary, risk: initial?.risk, observed_signs: initial?.observed_signs, differential_diagnoses: diffs})}\nFollow-up answers: ${JSON.stringify(cleanAnswers)}\nReviewed catalog: ${JSON.stringify(catalog)}\nBuild the final report now.`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch(`${BASE}/${encodeURIComponent(MODEL)}:generateContent`, {
        signal: controller.signal,
        method: "POST",
        headers: { "x-goog-api-key": geminiKey, "content-type": "application/json" },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: systemPrompt }] },
          contents: [{ role: "user", parts: [{ text: input }] }],
          generationConfig: {
            temperature: 0.15,
            maxOutputTokens: 2400,
            responseMimeType: "application/json",
            responseSchema: finalSchema,
          },
        }),
      });
      const payload = await response.json().catch(() => null);
      const raw = response.ok ? geminiText(payload) : null;
      if (!response.ok) console.error("finalize-case-report Gemini error", response.status, payload?.error?.status ?? "", payload?.error?.message ?? "");
      if (raw) {
        const parsed = JSON.parse(raw);
        const evidenceRows = catalog.filter((x: any) => x?.source_org && x?.source_url && x?.source_reviewed_at);
        finalResult = {
          code: "FINAL_REPORT_COMPLETE",
          report_stage: "final",
          assessment_id: assessmentId,
          ...parsed,
          evidence_verified: evidenceRows.length > 0,
          source_labels: [...new Set(evidenceRows.map((x: any) => cleanText(x.source_org)).filter(Boolean))].slice(0, 8),
          provider: "gemini",
          model: MODEL,
          provider_request_id: payload?.responseId ?? null,
          fast_fallback: false,
          generated_at: new Date().toISOString(),
        };
        usage = { ...(payload?.usageMetadata ?? {}), follow_up_fingerprint: fingerprint, mode: "gemini_structured", provider: "gemini" };
      }
    } catch (error) {
      console.error("finalize-case-report Gemini fallback", error);
      finalResult = fallback;
    } finally {
      clearTimeout(timer);
    }
  }

  await supabase.from("assessments").update({
    risk: finalResult.risk,
    status: "final_report",
    ai_analysis: finalResult,
    ai_model: finalResult.model ?? "catalog-fallback",
    ai_usage: usage,
    ai_generated_at: finalResult.generated_at,
  }).eq("id", assessmentId);

  await supabase.from("alerts").delete().eq("assessment_id", assessmentId);
  if (finalResult.risk === "red" || finalResult.risk === "orange") {
    await supabase.from("alerts").insert({
      farm_id: assessment.farm_id,
      assessment_id: assessmentId,
      risk: finalResult.risk,
      title: isArabic(language)
        ? (finalResult.risk === "red" ? "تنبيه صحي عاجل من Vet AI" : "حالة محتاجة مراجعة بيطرية")
        : (finalResult.risk === "red" ? "Urgent Vet AI health alert" : "Vet AI veterinary review alert"),
      details: finalResult.summary,
    });
  }
  return json(finalResult);
});