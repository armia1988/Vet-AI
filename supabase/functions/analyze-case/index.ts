import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json; charset=utf-8" },
});

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Missing authorization" }, 401);

  const { assessment_id } = await req.json().catch(() => ({}));
  if (!assessment_id || typeof assessment_id !== "string") {
    return json({ error: "assessment_id is required" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const supabase = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: assessment, error: assessmentError } = await supabase
    .from("assessments")
    .select("id,farm_id,media_path,symptom_notes,status,risk")
    .eq("id", assessment_id)
    .single();

  if (assessmentError || !assessment) {
    return json({ error: "Assessment not found or access denied" }, 404);
  }

  const { data: diseases, error: diseaseError } = await supabase
    .from("disease_catalog")
    .select("id,slug,display_name,animal_groups,default_risk,lab_confirmation_required,source_org,source_url")
    .order("display_name");

  if (diseaseError) return json({ error: "Knowledge base unavailable" }, 503);

  // Safety contract: never fabricate a veterinary diagnosis when validated inference
  // has not been configured. Keep the assessment in insufficient-data state.
  const providerKey = Deno.env.get("VET_AI_PROVIDER_KEY");
  if (!providerKey) {
    return json({
      code: "AI_PROVIDER_NOT_CONFIGURED",
      assessment_id,
      risk: "insufficient_data",
      message: "The protected clinical AI provider is not configured yet.",
      curated_disease_count: diseases?.length ?? 0,
    }, 503);
  }

  return json({
    code: "AI_PROVIDER_PENDING_IMPLEMENTATION",
    assessment_id,
    risk: "insufficient_data",
    message: "Provider credentials exist, but production clinical inference is not enabled until the validated inference contract is deployed.",
  }, 503);
});
