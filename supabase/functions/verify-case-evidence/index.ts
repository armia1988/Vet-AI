import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const MODEL = Deno.env.get("VET_AI_GEMINI_VERIFY_MODEL") ?? "gemini-3.5-flash-lite";
const BASE = "https://generativelanguage.googleapis.com/v1beta/models";
const OFFICIAL_SOURCE_TOKENS = [
  "cdc.gov",
  "aphis.usda.gov",
  "usda.gov",
  "gov.uk",
  "woah.org",
  "fao.org",
  "ec.europa.eu",
  "efsa.europa.eu",
  "inspection.canada.ca",
  "agriculture.gov.au",
  "ema.europa.eu",
];

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
});

const clean = (value: unknown) => String(value ?? "")
  .replace(/https?:\/\/\S+/gi, "")
  .replace(/\s{2,}/g, " ")
  .trim();

const cleanList = (value: unknown) => Array.isArray(value)
  ? value.map(clean).filter(Boolean)
  : [];

const modelText = (payload: any) => {
  for (const candidate of payload?.candidates ?? []) {
    const chunks: string[] = [];
    for (const part of candidate?.content?.parts ?? []) {
      if (part?.thought === true) continue;
      if (typeof part?.text === "string" && part.text.trim()) chunks.push(part.text);
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
  throw new Error("No complete JSON object in verification response");
};

const isOfficialTitle = (title: string) => {
  const lower = title.toLowerCase();
  return OFFICIAL_SOURCE_TOKENS.some((token) => lower.includes(token));
};

const suspicionFromConfidence = (confidence: string) =>
  confidence === "high" ? "high" : confidence === "moderate" ? "moderate" : "low";

Deno.serve(async (req: Request) => {
  try {
    if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
    const authorization = req.headers.get("Authorization");
    if (!authorization) return json({ error: "Missing authorization" }, 401);

    const body = await req.json().catch(() => ({}));
    const assessmentId = typeof body?.assessment_id === "string" ? body.assessment_id : "";
    const language = typeof body?.language === "string" ? body.language.toLowerCase() : "en";
    if (!assessmentId) return json({ error: "assessment_id is required" }, 400);

    const key = Deno.env.get("GEMINI_API_KEY");
    if (!key) return json({ code: "EVIDENCE_SEARCH_NOT_CONFIGURED" }, 503);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

    const { data: assessment, error: assessmentError } = await supabase
      .from("assessments")
      .select("id,farm_id,animal_group,symptom_notes,ai_analysis,ai_model,ai_usage,status")
      .eq("id", assessmentId)
      .single();
    if (assessmentError || !assessment) return json({ error: "Assessment not found or access denied" }, 404);

    const initial = assessment.ai_analysis && typeof assessment.ai_analysis === "object"
      ? assessment.ai_analysis
      : {};
    if (initial?.code !== "AI_ANALYSIS_COMPLETE") return json(initial);
    if (initial?.official_evidence_verified === true) return json(initial);
    if (initial?.group_match === "mismatch") return json(initial);

    const animalGroup = assessment.animal_group ?? initial?.animal_group ?? "livestock";
    const { data: allDiseases, error: catalogError } = await supabase
      .from("disease_catalog")
      .select("id,slug,display_name,animal_groups,cause,default_risk,treatment_summary,prevention_summary,owner_actions_summary,clinical_red_flags,isolation_guidance,lab_confirmation_required,zoonotic,reportable_or_listed,source_org,source_url,curation_status")
      .eq("curation_status", "reviewed")
      .order("display_name");
    if (catalogError || !allDiseases) return json(initial);

    const diseases = allDiseases.filter((d: any) =>
      Array.isArray(d.animal_groups) && d.animal_groups.includes(animalGroup)
    );
    if (!diseases.length) return json(initial);

    const ids = diseases.map((d: any) => d.id);
    const { data: signs } = await supabase
      .from("disease_signs")
      .select("disease_id,phase,sign,visible_in_image")
      .in("disease_id", ids);

    const compactCatalog = diseases.map((d: any) => ({
      slug: d.slug,
      name: d.display_name,
      cause: d.cause,
      reportable_or_listed: d.reportable_or_listed,
      zoonotic: d.zoonotic,
      official_reference: d.source_url,
      visible_signs: (signs ?? [])
        .filter((s: any) => s.disease_id === d.id && s.visible_in_image === true)
        .map((s: any) => s.sign),
    }));

    const initialDiffs = Array.isArray(initial?.differential_diagnoses)
      ? initial.differential_diagnoses.slice(0, 4)
      : [];
    const observedSigns = cleanList(initial?.observed_signs).slice(0, 12);
    const speciesObserved = clean(initial?.species_observed);
    const summary = clean(initial?.summary);
    const languageRule = language.startsWith("ar")
      ? "Return user-facing reasoning in clear professional Egyptian Arabic only."
      : `Return user-facing reasoning naturally in language code ${language}.`;

    const prompt = `You are the official-evidence verification stage for Vet AI. ${languageRule}

Your job is NOT to diagnose from scratch and NOT to overrule veterinary care. Verify which reviewed catalog condition is most compatible with the visible pattern and supplied history by using Google Search.

SEARCH RULES:
1. Use Google Search now, preferably one concise query and at most two.
2. Prefer and cite ONLY official government or intergovernmental animal/public-health sources from these domains: cdc.gov, aphis.usda.gov, usda.gov, gov.uk, woah.org, fao.org, ec.europa.eu, efsa.europa.eu, inspection.canada.ca, agriculture.gov.au, ema.europa.eu.
3. Ignore blogs, commercial veterinary pages, forums and social media for this verification.
4. Distinguish look-alike lesion TYPES, not just disease severity. Thick proliferative scabs/crusts around sheep/goat lips or muzzle are not the same thing as fresh vesicles/blisters/erosions. Foot-and-mouth disease should not be ranked first from mouth scabs alone; compatible vesicles/erosions plus salivation and/or foot lesions/lameness materially strengthen FMD. Orf/contagious ecthyma should be considered when sheep/goats have characteristic crusted proliferative lip/muzzle lesions.
5. If official evidence is insufficient, say so rather than forcing a disease.

CASE:
Animal group: ${animalGroup}
Species observed: ${speciesObserved || "uncertain"}
History/notes: ${clean(assessment.symptom_notes) || "none supplied"}
Visual summary: ${summary}
Observed visual signs: ${JSON.stringify(observedSigns)}
Initial differentials: ${JSON.stringify(initialDiffs.map((d: any) => ({ slug: d.catalog_slug, name: d.name, suspicion: d.suspicion })))}
Reviewed catalog: ${JSON.stringify(compactCatalog)}

Return ONLY one JSON object with this exact shape:
{
  "best_slug": "catalog slug or empty string",
  "confidence": "low|moderate|high",
  "reasoning": "short evidence-based explanation",
  "supported_signs": ["short sign"],
  "conflicting_or_missing_signs": ["short sign"],
  "cannot_exclude_reportable_disease": true_or_false
}`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 6500);
    let payload: any = null;
    try {
      const response = await fetch(`${BASE}/${encodeURIComponent(MODEL)}:generateContent`, {
        method: "POST",
        signal: controller.signal,
        headers: { "x-goog-api-key": key, "content-type": "application/json" },
        body: JSON.stringify({
          contents: [{ role: "user", parts: [{ text: prompt }] }],
          tools: [{ google_search: {} }],
          generationConfig: {
            candidateCount: 1,
            temperature: 0,
            maxOutputTokens: 1100,
            thinkingConfig: { thinkingLevel: "low" },
          },
        }),
      });
      payload = await response.json().catch(() => null);
      if (!response.ok || !payload) {
        console.warn("verify-case-evidence provider failed", response.status, payload?.error?.status ?? "");
        return json({ ...initial, official_evidence_verified: false, evidence_search_used: true });
      }
    } catch (error) {
      console.warn("verify-case-evidence exception", String(error));
      return json({ ...initial, official_evidence_verified: false, evidence_search_used: true });
    } finally {
      clearTimeout(timer);
    }

    const candidate = payload?.candidates?.[0];
    const raw = modelText(payload);
    let verification: any = null;
    try { verification = raw ? parseJsonSafely(raw) : null; } catch (_) { verification = null; }
    if (!verification) {
      return json({ ...initial, official_evidence_verified: false, evidence_search_used: true });
    }

    const metadata = candidate?.groundingMetadata ?? {};
    const chunks = Array.isArray(metadata?.groundingChunks) ? metadata.groundingChunks : [];
    const officialSources = chunks
      .map((chunk: any) => ({
        title: clean(chunk?.web?.title),
        uri: String(chunk?.web?.uri ?? ""),
      }))
      .filter((source: any) => source.title && source.uri && isOfficialTitle(source.title))
      .slice(0, 6);
    const queries = Array.isArray(metadata?.webSearchQueries)
      ? metadata.webSearchQueries.map(clean).filter(Boolean).slice(0, 2)
      : [];

    if (!officialSources.length) {
      return json({
        ...initial,
        official_evidence_verified: false,
        evidence_search_used: true,
        official_evidence_queries: queries,
      });
    }

    const bestSlug = String(verification?.best_slug ?? "");
    const bestDisease: any = diseases.find((d: any) => d.slug === bestSlug);
    if (!bestDisease) {
      return json({
        ...initial,
        official_evidence_verified: false,
        evidence_search_used: true,
        official_evidence_sources: officialSources,
        official_evidence_queries: queries,
      });
    }

    const confidence = ["low", "moderate", "high"].includes(String(verification?.confidence))
      ? String(verification.confidence)
      : "low";
    const reasoning = clean(verification?.reasoning);
    const existing = initialDiffs.find((d: any) => d?.catalog_slug === bestSlug);
    const verifiedTop = {
      catalog_slug: bestDisease.slug,
      name: clean(existing?.name || bestDisease.display_name),
      suspicion: suspicionFromConfidence(confidence),
      reasoning: reasoning || clean(existing?.reasoning),
      cause: clean(bestDisease.cause),
      default_risk: bestDisease.default_risk,
      zoonotic: bestDisease.zoonotic,
      reportable_or_listed: bestDisease.reportable_or_listed,
      lab_confirmation_required: bestDisease.lab_confirmation_required,
      diagnostics_required: Boolean(bestDisease.lab_confirmation_required),
      prevention_summary: clean(bestDisease.prevention_summary),
      treatment_summary: clean(bestDisease.treatment_summary),
      owner_actions_summary: clean(bestDisease.owner_actions_summary),
      clinical_red_flags: cleanList(bestDisease.clinical_red_flags),
      isolation_guidance: clean(bestDisease.isolation_guidance),
      evidence_verified: true,
    };

    const reordered = [
      verifiedTop,
      ...initialDiffs.filter((d: any) => d?.catalog_slug !== bestSlug),
    ].slice(0, 4);

    const verified = {
      ...initial,
      differential_diagnoses: reordered,
      official_evidence_verified: true,
      evidence_search_used: true,
      official_evidence_model: MODEL,
      official_evidence_confidence: confidence,
      official_evidence_reasoning: reasoning,
      official_evidence_supported_signs: cleanList(verification?.supported_signs).slice(0, 8),
      official_evidence_conflicting_or_missing_signs: cleanList(verification?.conflicting_or_missing_signs).slice(0, 8),
      cannot_exclude_reportable_disease: verification?.cannot_exclude_reportable_disease === true,
      official_evidence_sources: officialSources,
      official_evidence_queries: queries,
      evidence_verified_at: new Date().toISOString(),
    };

    const { error: saveError } = await supabase.from("assessments").update({
      differential_diagnoses: reordered,
      ai_analysis: verified,
      ai_usage: {
        ...(assessment.ai_usage ?? {}),
        official_evidence_verified: true,
        official_evidence_model: MODEL,
        official_evidence_source_titles: officialSources.map((s: any) => s.title),
        official_evidence_queries: queries,
      },
      ai_generated_at: verified.evidence_verified_at,
    }).eq("id", assessmentId);
    if (saveError) console.error("verify-case-evidence save failed", saveError.message);

    return json(verified);
  } catch (error) {
    console.error("verify-case-evidence unhandled", error);
    return json({ code: "EVIDENCE_VERIFY_INTERNAL_ERROR" }, 500);
  }
});
