import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const OPENAI_MODEL = "gpt-5.6-terra";
const MAX_IMAGE_BYTES = 12 * 1024 * 1024;

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8" },
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
  if (typeof payload?.output_text === "string" && payload.output_text.trim()) {
    return payload.output_text;
  }
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

const maxRisk = (a: string, b: string) =>
  (riskRank[a] ?? -1) >= (riskRank[b] ?? -1) ? a : b;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Missing authorization" }, 401);

  const body = await req.json().catch(() => ({}));
  const assessmentId = body?.assessment_id;
  const requestedLanguage = typeof body?.language === "string" && /^[a-zA-Z-]{2,12}$/.test(body.language)
    ? body.language
    : "en";

  if (!assessmentId || typeof assessmentId !== "string") {
    return json({ error: "assessment_id is required" }, 400);
  }

  const providerKey = Deno.env.get("VET_AI_PROVIDER_KEY");
  if (!providerKey) {
    return json({ code: "AI_PROVIDER_NOT_CONFIGURED", risk: "insufficient_data" }, 503);
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

  if (assessmentError || !assessment) {
    return json({ error: "Assessment not found or access denied" }, 404);
  }
  if (!assessment.media_path) return json({ error: "Assessment has no image" }, 400);

  const animalGroup = assessment.animal_group ?? "livestock";

  const { data: diseaseRows, error: diseaseError } = await supabase
    .from("disease_catalog")
    .select("id,slug,display_name,animal_groups,default_risk,isolation_guidance,lab_confirmation_required,source_org,source_url")
    .order("display_name");
  if (diseaseError || !diseaseRows) return json({ error: "Knowledge base unavailable" }, 503);

  const diseases = diseaseRows.filter((d: any) =>
    Array.isArray(d.animal_groups) && d.animal_groups.includes(animalGroup)
  );
  if (!diseases.length) return json({ error: "No curated knowledge for animal group" }, 422);

  const ids = diseases.map((d: any) => d.id);
  const { data: signRows, error: signError } = await supabase
    .from("disease_signs")
    .select("disease_id,phase,sign,visible_in_image,visible_in_video,sensor_detectable")
    .in("disease_id", ids);
  if (signError) return json({ error: "Knowledge signs unavailable" }, 503);

  const catalogContext = diseases.map((d: any) => ({
    slug: d.slug,
    name: d.display_name,
    default_risk: d.default_risk,
    lab_confirmation_required: d.lab_confirmation_required,
    source_org: d.source_org,
    source_url: d.source_url,
    signs: (signRows ?? [])
      .filter((s: any) => s.disease_id === d.id)
      .map((s: any) => ({ phase: s.phase, sign: s.sign, visible_in_image: s.visible_in_image })),
  }));

  const { data: mediaBlob, error: mediaError } = await supabase.storage
    .from("diagnostic-media")
    .download(assessment.media_path);
  if (mediaError || !mediaBlob) return json({ error: "Image unavailable or access denied" }, 404);
  if (mediaBlob.size > MAX_IMAGE_BYTES) return json({ error: "Image is too large for analysis" }, 413);

  const mime = mimeFromPath(assessment.media_path);
  if (!mime) {
    return json({
      code: "UNSUPPORTED_IMAGE_FORMAT",
      message: "Use JPEG, PNG, WEBP or GIF for AI analysis.",
      risk: "insufficient_data",
    }, 415);
  }

  const imageBytes = new Uint8Array(await mediaBlob.arrayBuffer());
  const imageUrl = `data:${mime};base64,${bytesToBase64(imageBytes)}`;
  const validSlugs = new Set(diseases.map((d: any) => d.slug));

  const developerPrompt = `You are the veterinary decision-support inference layer for Vet AI. This is a high-stakes animal-health triage system, not an autonomous veterinarian.\n\nSafety rules:\n1. Never claim a definitive diagnosis from one image. Describe visible signs separately from differential possibilities.\n2. Use only disease slugs present in the supplied curated catalog when naming a disease differential. If the evidence does not fit, return an empty differential list and explain uncertainty.\n3. Never invent a numerical confidence percentage. Use low/moderate/high suspicion only.\n4. If image quality is insufficient, say so. Symptoms supplied by the user may still justify urgent triage.\n5. Red means critical/urgent animal-health or biosecurity concern. Orange means prompt veterinary assessment is warranted. Yellow means monitor/follow up. none means no current concerning signal from available evidence. insufficient_data means the available information cannot support triage.\n6. For suspected reportable/high-consequence infectious disease patterns, favor biosecurity and urgent veterinary/competent-authority review over reassurance.\n7. Laboratory confirmation is required whenever the curated disease entry says so.\n8. Do not provide drug doses, prescription instructions, or treatment regimens.\n9. Write all user-facing text in language code: ${requestedLanguage}.\n10. Keep the response concise and operational for farmers and veterinarians.`;

  const userPrompt = `Animal group selected by the user: ${animalGroup}\nUser symptoms/history notes: ${assessment.symptom_notes?.trim() || "No symptom notes supplied."}\n\nCurated veterinary knowledge (authoritative source URLs are included and must not be replaced with invented sources):\n${JSON.stringify(catalogContext)}\n\nAnalyze the attached animal image together with the notes. Return visible findings, a cautious differential shortlist from the catalog, triage risk, immediate non-pharmacologic safety actions, whether isolation/biosecurity is advisable, whether urgent veterinary review is needed, whether lab confirmation is needed, and the most useful follow-up questions.`;

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
      reasoning: { effort: "medium" },
      max_output_tokens: 2200,
      input: [
        { role: "developer", content: [{ type: "input_text", text: developerPrompt }] },
        {
          role: "user",
          content: [
            { type: "input_text", text: userPrompt },
            { type: "input_image", image_url: imageUrl, detail: "high" },
          ],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "vet_ai_assessment",
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: [
              "image_quality", "species_observed", "summary", "observed_signs",
              "differentials", "risk", "urgent_vet_review", "isolation_recommended",
              "lab_confirmation_required", "immediate_actions", "follow_up_questions",
              "confidence_statement"
            ],
            properties: {
              image_quality: { type: "string", enum: ["insufficient", "limited", "adequate"] },
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
    console.error("Vet AI provider error", providerResponse.status, providerRequestId);
    const code = providerResponse.status === 429 ? "AI_PROVIDER_RATE_LIMIT" : "AI_PROVIDER_ERROR";
    return json({
      code,
      risk: "insufficient_data",
      message: providerResponse.status === 429
        ? "AI analysis is temporarily rate-limited. Please retry shortly."
        : "The protected AI analysis service could not complete this case.",
      provider_request_id: providerRequestId,
    }, providerResponse.status === 429 ? 503 : 502);
  }

  const rawText = responseText(providerPayload);
  if (!rawText) {
    return json({ code: "AI_EMPTY_RESPONSE", risk: "insufficient_data" }, 502);
  }

  let modelResult: any;
  try {
    modelResult = JSON.parse(rawText);
  } catch {
    return json({ code: "AI_INVALID_RESPONSE", risk: "insufficient_data" }, 502);
  }

  const enrichedDifferentials = (Array.isArray(modelResult.differentials) ? modelResult.differentials : [])
    .filter((d: any) => validSlugs.has(d.catalog_slug))
    .slice(0, 5)
    .map((d: any) => {
      const catalog = diseases.find((x: any) => x.slug === d.catalog_slug)!;
      return {
        catalog_slug: catalog.slug,
        name: catalog.display_name,
        suspicion: d.suspicion,
        reasoning: d.reasoning,
        default_risk: catalog.default_risk,
        lab_confirmation_required: catalog.lab_confirmation_required,
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

  if (modelResult.image_quality === "insufficient" && !assessment.symptom_notes?.trim() && enrichedDifferentials.length === 0) {
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

  const { error: updateError } = await supabase
    .from("assessments")
    .update({
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
    })
    .eq("id", assessmentId);

  if (updateError) {
    console.error("Assessment update failed", updateError.message);
    return json({ code: "AI_RESULT_SAVE_FAILED", risk: "insufficient_data" }, 500);
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
