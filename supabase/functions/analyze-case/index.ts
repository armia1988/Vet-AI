import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const OPENAI_MODEL = Deno.env.get("VET_AI_ANALYSIS_MODEL") ?? "gpt-5.6-luna";
const MAX_IMAGE_BYTES = 12 * 1024 * 1024;

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8" },
});

const operational = (code: string, message: string, extra: Record<string, unknown> = {}) => json({
  code,
  risk: "insufficient_data",
  message,
  ...extra,
});

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

const responseText = (payload: any): string | null => {
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) return payload.output_text;
  for (const item of payload?.output ?? []) {
    if (item?.type !== "message") continue;
    for (const part of item?.content ?? []) {
      if (part?.type === "output_text" && typeof part.text === "string") return part.text;
    }
  }
  return null;
};

const riskRank: Record<string, number> = {
  insufficient_data: -1,
  none: 0,
  yellow: 1,
  orange: 2,
  red: 3,
};
const maxRisk = (a: string, b: string) => (riskRank[a] ?? -1) >= (riskRank[b] ?? -1) ? a : b;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Missing authorization" }, 401);

  const body = await req.json().catch(() => ({}));
  const assessmentId = body?.assessment_id;
  const requestedLanguage = typeof body?.language === "string" && /^[a-zA-Z-]{2,12}$/.test(body.language)
    ? body.language
    : "en";
  if (!assessmentId || typeof assessmentId !== "string") return json({ error: "assessment_id is required" }, 400);

  const providerKey = Deno.env.get("VET_AI_PROVIDER_KEY") ?? Deno.env.get("OPENAI_API_KEY");
  if (!providerKey) {
    console.error("Vet AI provider key is not configured for analyze-case");
    return operational(
      "AI_PROVIDER_NOT_CONFIGURED",
      "The protected AI provider key is not available to the analysis service.",
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

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
    .select("id,slug,display_name,animal_groups,agent_type,cause,condition_type,body_systems,species_scope,preclinical_notes,diagnostics_summary,prevention_summary,epidemiology_summary,default_risk,isolation_guidance,lab_confirmation_required,reportable_or_listed,zoonotic,source_org,source_url,source_reviewed_at,curation_status")
    .eq("curation_status", "reviewed")
    .order("display_name");
  if (diseaseError || !diseaseRows) {
    console.error("Vet AI knowledge catalog read failed", diseaseError?.message);
    return operational("KNOWLEDGE_BASE_UNAVAILABLE", "The reviewed veterinary knowledge base is temporarily unavailable.");
  }

  const diseases = diseaseRows.filter((d: any) => Array.isArray(d.animal_groups) && d.animal_groups.includes(animalGroup));
  if (!diseases.length) {
    return operational("KNOWLEDGE_GAP", "No reviewed production knowledge is available for the selected animal group yet.");
  }

  const ids = diseases.map((d: any) => d.id);
  const { data: signRows, error: signError } = await supabase
    .from("disease_signs")
    .select("disease_id,phase,sign,visible_in_image,visible_in_video,sensor_detectable")
    .in("disease_id", ids);
  if (signError) {
    console.error("Vet AI knowledge sign read failed", signError.message);
    return operational("KNOWLEDGE_BASE_UNAVAILABLE", "The reviewed veterinary sign library is temporarily unavailable.");
  }

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
    epidemiology_summary: d.epidemiology_summary,
    default_risk: d.default_risk,
    reportable_or_listed: d.reportable_or_listed,
    zoonotic: d.zoonotic,
    isolation_guidance: d.isolation_guidance,
    lab_confirmation_required: d.lab_confirmation_required,
    source_org: d.source_org,
    source_url: d.source_url,
    source_reviewed_at: d.source_reviewed_at,
    signs: (signRows ?? [])
      .filter((s: any) => s.disease_id === d.id)
      .map((s: any) => ({ phase: s.phase, sign: s.sign, visible_in_image: s.visible_in_image, sensor_detectable: s.sensor_detectable })),
  }));

  const { data: mediaBlob, error: mediaError } = await supabase.storage.from("diagnostic-media").download(assessment.media_path);
  if (mediaError || !mediaBlob) return json({ error: "Image unavailable or access denied" }, 404);
  if (mediaBlob.size > MAX_IMAGE_BYTES) return operational("IMAGE_TOO_LARGE", "The image is too large for safe analysis.");

  const mime = mimeFromPath(assessment.media_path);
  if (!mime) return operational("UNSUPPORTED_IMAGE_FORMAT", "Use JPEG, PNG, WEBP or GIF for AI analysis.");
  const imageBytes = new Uint8Array(await mediaBlob.arrayBuffer());
  const imageUrl = `data:${mime};base64,${bytesToBase64(imageBytes)}`;
  const validSlugs = new Set(diseases.map((d: any) => d.slug));

  const developerPrompt = `You are the veterinary decision-support inference layer for Vet AI. This is a high-stakes animal-health triage system, not an autonomous veterinarian.

Safety rules:
1. First verify whether the image is compatible with the animal group selected by the user (livestock, poultry, or dogs). If the image is a human, unrelated object, clearly different animal group, or too ambiguous to establish compatibility, set group_match to mismatch or uncertain. For mismatch, do not name disease differentials and do not infer animal disease from the image.
2. Never claim a definitive diagnosis from one image. Separate visible findings, history, sensor-compatible signs, and differential possibilities.
3. Use only disease/condition slugs present in the supplied reviewed catalog when naming a differential. The catalog includes diseases, disease complexes, syndromes and inflammatory conditions. If evidence does not fit, return an empty differential list.
4. Never invent numerical confidence percentages. Use low/moderate/high suspicion only.
5. Preclinical signs are useful for questions and monitoring but cannot be falsely claimed as visible when they are not visible.
6. Red means critical/urgent animal-health or biosecurity concern. Orange means prompt veterinary assessment. Yellow means monitor/follow up. none means no current concerning signal from available evidence. insufficient_data means evidence cannot support triage.
7. For suspected reportable, zoonotic or high-consequence infectious patterns, favor biosecurity, PPE where appropriate, movement restriction and urgent veterinary/competent-authority review over reassurance.
8. Laboratory/diagnostic confirmation is required whenever the reviewed entry says so or the differential cannot be safely distinguished clinically.
9. Do not provide drug doses, prescription instructions or treatment regimens.
10. Write all user-facing text in language code: ${requestedLanguage}.
11. Keep conclusions operational, cautious and explicit about uncertainty.`;

  const userPrompt = `Selected animal group: ${animalGroup}
User symptoms/history notes: ${assessment.symptom_notes?.trim() || "No symptom notes supplied."}

Reviewed veterinary knowledge for this selected group:
${JSON.stringify(catalogContext)}

Analyze the image and notes. Check selected-group compatibility before any disease reasoning. Return visible findings, cautious reviewed-catalog differential possibilities, triage risk, immediate non-pharmacologic safety actions, isolation/biosecurity needs, urgent veterinary review need, laboratory/diagnostic confirmation need, and useful follow-up questions.`;

  const providerResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${providerKey}`,
      "Content-Type": "application/json",
      "X-Client-Request-Id": crypto.randomUUID(),
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      store: false,
      reasoning: { effort: "low" },
      max_output_tokens: 1400,
      input: [
        { role: "developer", content: [{ type: "input_text", text: developerPrompt }] },
        { role: "user", content: [{ type: "input_text", text: userPrompt }, { type: "input_image", image_url: imageUrl, detail: "high" }] },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "vet_ai_assessment_v2",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: [
              "image_quality", "group_match", "group_match_reason", "species_observed", "summary",
              "observed_signs", "differentials", "risk", "urgent_vet_review", "isolation_recommended",
              "lab_confirmation_required", "immediate_actions", "follow_up_questions", "confidence_statement"
            ],
            properties: {
              image_quality: { type: "string", enum: ["insufficient", "limited", "adequate"] },
              group_match: { type: "string", enum: ["match", "mismatch", "uncertain"] },
              group_match_reason: { type: "string" },
              species_observed: { type: "string" },
              summary: { type: "string" },
              observed_signs: { type: "array", items: { type: "string" } },
              differentials: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: ["catalog_slug", "suspicion", "reasoning"],
                  properties: {
                    catalog_slug: { type: "string" },
                    suspicion: { type: "string", enum: ["low", "moderate", "high"] },
                    reasoning: { type: "string" }
                  }
                }
              },
              risk: { type: "string", enum: ["none", "yellow", "orange", "red", "insufficient_data"] },
              urgent_vet_review: { type: "boolean" },
              isolation_recommended: { type: "boolean" },
              lab_confirmation_required: { type: "boolean" },
              immediate_actions: { type: "array", items: { type: "string" } },
              follow_up_questions: { type: "array", items: { type: "string" } },
              confidence_statement: { type: "string" }
            }
          }
        }
      }
    }),
  });

  const providerRequestId = providerResponse.headers.get("x-request-id");
  const providerPayload = await providerResponse.json().catch(() => null);
  if (!providerResponse.ok || !providerPayload) {
    const providerCode = String(providerPayload?.error?.code ?? providerPayload?.error?.type ?? "");
    console.error("Vet AI provider error", providerResponse.status, providerCode, providerRequestId);
    if (providerResponse.status === 401 || providerResponse.status === 403) {
      return operational("AI_PROVIDER_AUTH_ERROR", "The AI provider rejected the server credential.", { provider_request_id: providerRequestId });
    }
    if (providerResponse.status === 429 && (providerCode.includes("quota") || providerCode.includes("billing"))) {
      return operational("AI_PROVIDER_QUOTA", "The AI provider account has no available API quota or billing capacity.", { provider_request_id: providerRequestId });
    }
    if (providerResponse.status === 429) {
      return operational("AI_PROVIDER_RATE_LIMIT", "AI analysis is temporarily rate-limited. Please retry later.", { provider_request_id: providerRequestId });
    }
    return operational("AI_PROVIDER_ERROR", "The protected AI provider could not complete this case.", { provider_request_id: providerRequestId });
  }

  const rawText = responseText(providerPayload);
  if (!rawText) return operational("AI_EMPTY_RESPONSE", "The AI provider returned no usable assessment text.", { provider_request_id: providerRequestId });

  let modelResult: any;
  try {
    modelResult = JSON.parse(rawText);
  } catch {
    return operational("AI_INVALID_RESPONSE", "The AI provider returned a response that did not match the safety schema.", { provider_request_id: providerRequestId });
  }

  if (modelResult.group_match === "mismatch") {
    const mismatchResult = {
      code: "SPECIES_GROUP_MISMATCH",
      assessment_id: assessmentId,
      animal_group: animalGroup,
      image_quality: modelResult.image_quality,
      species_observed: modelResult.species_observed,
      summary: modelResult.group_match_reason || modelResult.summary,
      observed_signs: [],
      differential_diagnoses: [],
      risk: "insufficient_data",
      urgent_vet_review: false,
      isolation_recommended: false,
      lab_confirmation_required: false,
      immediate_actions: [],
      follow_up_questions: [],
      confidence_statement: modelResult.confidence_statement,
      model: OPENAI_MODEL,
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
      ai_model: OPENAI_MODEL,
      ai_provider_request_id: providerRequestId,
      ai_usage: providerPayload.usage ?? {},
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
        name: catalog.display_name,
        condition_type: catalog.condition_type,
        suspicion: d.suspicion,
        reasoning: d.reasoning,
        default_risk: catalog.default_risk,
        zoonotic: catalog.zoonotic,
        reportable_or_listed: catalog.reportable_or_listed,
        lab_confirmation_required: catalog.lab_confirmation_required,
        diagnostics_summary: catalog.diagnostics_summary,
        source_org: catalog.source_org,
        source_url: catalog.source_url,
        isolation_guidance: catalog.isolation_guidance,
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

  const isolationRecommended = modelResult.isolation_recommended === true || enrichedDifferentials.some(
    (d: any) => (d.suspicion === "moderate" || d.suspicion === "high") && Boolean(d.isolation_guidance)
  );
  const labRequired = modelResult.lab_confirmation_required === true || enrichedDifferentials.some(
    (d: any) => (d.suspicion === "moderate" || d.suspicion === "high") && d.lab_confirmation_required === true
  );

  const result = {
    code: "AI_ANALYSIS_COMPLETE",
    assessment_id: assessmentId,
    animal_group: animalGroup,
    group_match: modelResult.group_match,
    image_quality: modelResult.image_quality,
    species_observed: modelResult.species_observed,
    summary: modelResult.summary,
    observed_signs: Array.isArray(modelResult.observed_signs) ? modelResult.observed_signs.slice(0, 12) : [],
    differential_diagnoses: enrichedDifferentials,
    risk: finalRisk,
    urgent_vet_review: modelResult.urgent_vet_review === true,
    isolation_recommended: isolationRecommended,
    lab_confirmation_required: labRequired,
    immediate_actions: Array.isArray(modelResult.immediate_actions) ? modelResult.immediate_actions.slice(0, 8) : [],
    follow_up_questions: Array.isArray(modelResult.follow_up_questions) ? modelResult.follow_up_questions.slice(0, 8) : [],
    confidence_statement: modelResult.confidence_statement,
    model: OPENAI_MODEL,
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
    ai_model: OPENAI_MODEL,
    ai_provider_request_id: providerRequestId,
    ai_usage: providerPayload.usage ?? {},
    ai_generated_at: result.generated_at,
  }).eq("id", assessmentId);
  if (updateError) {
    console.error("Vet AI assessment save failed", updateError.message);
    return operational("AI_RESULT_SAVE_FAILED", "The assessment was generated but could not be saved safely.");
  }

  await supabase.from("alerts").delete().eq("assessment_id", assessmentId);
  if (result.risk === "red" || result.risk === "orange") {
    await supabase.from("alerts").insert({
      farm_id: assessment.farm_id,
      assessment_id: assessmentId,
      risk: result.risk,
      title: result.risk === "red" ? "Critical Vet AI health alert" : "Vet AI veterinary review alert",
      details: result.summary,
    });
  }

  return json(result);
});
