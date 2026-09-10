import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
    },
  });

const hex = (bytes: Uint8Array) =>
  Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");

async function sha256(value: string) {
  return hex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
  );
}

function serviceKey(): string {
  const modern = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (modern) {
    try {
      const keys = JSON.parse(modern);
      if (keys?.default) return keys.default;
    } catch (_) {
      // Fall back to the legacy service-role variable.
    }
  }
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!legacy) throw new Error("Missing Supabase service key");
  return legacy;
}

type StringMap = Record<string, string>;

type Decision = {
  category: string;
  title: string;
  risk: "yellow" | "orange" | "red";
  shouldSurface: boolean;
  temperatureC: number | null;
};

function asRecord(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function toStringMap(value: unknown): StringMap {
  const source = asRecord(value);
  const result: StringMap = {};
  for (const [key, raw] of Object.entries(source)) {
    if (raw == null) continue;
    if (typeof raw === "string" || typeof raw === "number" || typeof raw === "boolean") {
      result[key] = String(raw);
    }
  }
  return result;
}

function finiteNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const parsed = Number(String(value ?? "").replace(",", "."));
  return Number.isFinite(parsed) ? parsed : null;
}

function nonNegativeInt(value: unknown): number {
  const parsed = Number.parseInt(String(value ?? "0"), 10);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function containsAny(haystack: string, needles: string[]) {
  return needles.some((needle) => haystack.includes(needle));
}

function isActive(values: StringMap) {
  if (Object.keys(values).length === 0) return true;
  const keys = ["State", "IsMotion", "Motion", "Alarm", "Active", "Detected", "LogicalState"];
  for (const key of keys) {
    const raw = values[key];
    if (raw == null) continue;
    const value = raw.trim().toLowerCase();
    if (["true", "1", "on", "active", "start", "started", "detected", "alarm"].includes(value)) return true;
    if (["false", "0", "off", "inactive", "stop", "stopped", "clear", "cleared"].includes(value)) return false;
  }
  return true;
}

function firstTemperature(values: StringMap): number | null {
  const keys = ["Temperature", "MaxTemperature", "maxTemperature", "temperature", "temperatureC"];
  for (const key of keys) {
    const raw = values[key];
    if (raw == null) continue;
    const match = raw.match(/-?\d+(?:\.\d+)?/);
    const parsed = match ? Number(match[0]) : Number.NaN;
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
}

function classify(topic: string, values: StringMap, criticalTemperatureC: number): Decision {
  const haystack = `${topic.toLowerCase()} ${Object.entries(values).map(([k, v]) => `${k}=${v}`).join(" ").toLowerCase()}`;
  const active = isActive(values);
  const temperature = firstTemperature(values);

  if (containsAny(haystack, ["fire", "flame", "smoke"])) {
    return {
      category: "fire",
      title: "Fire / smoke event",
      risk: active ? "red" : "yellow",
      shouldSurface: active,
      temperatureC: null,
    };
  }

  if (containsAny(haystack, ["temperature", "thermometry", "thermal", "overheat", "high temp"])) {
    const critical = temperature != null && temperature >= criticalTemperatureC;
    return {
      category: "thermal",
      title: temperature == null ? "Thermal event" : `Thermal event ${temperature.toFixed(1)} °C`,
      risk: critical ? "red" : "orange",
      shouldSurface: active || temperature != null,
      temperatureC: temperature,
    };
  }

  if (containsAny(haystack, ["intrusion", "linecross", "line crossing", "region entrance", "regionexit", "fielddetector"])) {
    return {
      category: "intrusion",
      title: "Intrusion / zone event",
      risk: active ? "orange" : "yellow",
      shouldSurface: active,
      temperatureC: null,
    };
  }

  if (containsAny(haystack, ["motion", "ismotion", "cellmotion"])) {
    return {
      category: "motion",
      title: "Motion detected",
      risk: "orange",
      shouldSurface: active,
      temperatureC: null,
    };
  }

  if (containsAny(haystack, ["person", "human", "face"])) {
    return {
      category: "person",
      title: "Person / human event",
      risk: "yellow",
      shouldSurface: active,
      temperatureC: null,
    };
  }

  if (containsAny(haystack, ["vehicle", "car", "truck"])) {
    return {
      category: "vehicle",
      title: "Vehicle event",
      risk: "yellow",
      shouldSurface: active,
      temperatureC: null,
    };
  }

  return {
    category: "camera_event",
    title: topic || "Camera event",
    risk: "yellow",
    shouldSurface: active,
    temperatureC: null,
  };
}

function validTimestamp(value: unknown): string {
  const raw = String(value ?? "").trim();
  if (!raw) return new Date().toISOString();
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? new Date().toISOString() : date.toISOString();
}

async function dispatchPush(alertId: string, serviceRoleKey: string) {
  const base = Deno.env.get("SUPABASE_URL")!;
  try {
    await fetch(`${base}/functions/v1/vet-ai-apns-push`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({ alert_id: alertId }),
    });
  } catch (_) {
    // Alert persistence must not fail because push delivery is unavailable.
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const body = await req.json().catch(() => ({}));
  const gatewayUid = String(body?.gateway_device_uid ?? "").trim();
  const gatewayToken = String(body?.gateway_device_token ?? "").trim();
  const kind = String(body?.kind ?? "heartbeat").trim().toLowerCase();
  if (!gatewayUid || !gatewayToken) {
    return json({ error: "gateway_device_uid and gateway_device_token are required" }, 401);
  }
  if (!["heartbeat", "event", "thermal_sample"].includes(kind)) {
    return json({ error: "Unsupported gateway message kind" }, 400);
  }

  const key = serviceKey();
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: gateway, error: gatewayError } = await admin
    .from("sensor_devices")
    .select("id,farm_id,active,device_type,device_secret_hash")
    .eq("device_uid", gatewayUid)
    .maybeSingle();

  if (gatewayError || !gateway || gateway.active !== true || gateway.device_type !== "camera_gateway") {
    return json({ error: "Unknown or inactive camera gateway" }, 401);
  }
  if (!gateway.device_secret_hash || await sha256(gatewayToken) !== gateway.device_secret_hash) {
    return json({ error: "Invalid camera gateway token" }, 401);
  }

  const now = new Date().toISOString();
  await admin.from("sensor_devices").update({ last_seen_at: now, updated_at: now }).eq("id", gateway.id);

  const runtime = asRecord(body?.runtime);
  const heartbeatPayload: Record<string, unknown> = {
    gateway_device_id: gateway.id,
    farm_id: gateway.farm_id,
    last_heartbeat_at: now,
    updated_at: now,
  };
  if (kind === "heartbeat") {
    heartbeatPayload.agent_version = String(body?.agent_version ?? "").slice(0, 80) || null;
    heartbeatPayload.hostname = String(body?.hostname ?? "").slice(0, 180) || null;
    heartbeatPayload.platform = String(body?.platform ?? "").slice(0, 180) || null;
    heartbeatPayload.cameras_configured = nonNegativeInt(body?.cameras_configured);
    heartbeatPayload.cameras_online = nonNegativeInt(body?.cameras_online);
    heartbeatPayload.events_forwarded = nonNegativeInt(body?.events_forwarded);
    heartbeatPayload.thermal_samples = nonNegativeInt(body?.thermal_samples);
    heartbeatPayload.last_error = String(body?.last_error ?? "").slice(0, 1200) || null;
    heartbeatPayload.runtime = runtime;
  }

  const { error: statusError } = await admin
    .from("camera_gateway_status")
    .upsert(heartbeatPayload, { onConflict: "gateway_device_id" });
  if (statusError) return json({ error: `Gateway status update failed: ${statusError.message}` }, 500);

  if (kind === "heartbeat") {
    return json({ ok: true, kind, server_time: now });
  }

  const cameraUid = String(body?.camera_uid ?? "").trim();
  if (!cameraUid) return json({ error: "camera_uid is required" }, 400);

  const { data: camera, error: cameraError } = await admin
    .from("sensor_devices")
    .select("id,farm_id,device_uid,device_type,active,controller_model,display_name,capabilities")
    .eq("device_uid", cameraUid)
    .eq("farm_id", gateway.farm_id)
    .maybeSingle();

  if (cameraError || !camera || camera.active !== true || !["ip_camera", "thermal_camera"].includes(camera.device_type)) {
    return json({ error: "Camera is not registered and active on this gateway farm" }, 403);
  }

  const capabilities = asRecord(camera.capabilities);
  const cameraName = String(
    capabilities.camera_name ?? camera.display_name ?? camera.controller_model ?? camera.device_uid,
  );
  const configuredThreshold = finiteNumber(capabilities.thermal_alert_threshold_c);
  const threshold = configuredThreshold != null && configuredThreshold >= 30 && configuredThreshold <= 60
    ? configuredThreshold
    : 41.0;

  let topic = String(body?.topic ?? "").trim();
  const values = toStringMap(body?.values);
  let eventTime = validTimestamp(body?.utc_time);

  if (kind === "thermal_sample") {
    const maxTemperature = finiteNumber(body?.max_temperature_c);
    const minTemperature = finiteNumber(body?.min_temperature_c);
    const averageTemperature = finiteNumber(body?.average_temperature_c);
    if (maxTemperature == null) return json({ error: "max_temperature_c is required" }, 400);
    topic = topic || "vetai/thermal/rule";
    values.MaxTemperature = String(maxTemperature);
    if (minTemperature != null) values.MinTemperature = String(minTemperature);
    if (averageTemperature != null) values.AverageTemperature = String(averageTemperature);
    values.State = maxTemperature >= threshold ? "true" : "false";
    eventTime = validTimestamp(body?.utc_time);

    // Continuous thermal polling is telemetry. Only persist an alert when the
    // camera's real maximum temperature crosses its configured Vet AI threshold.
    if (maxTemperature < threshold) {
      return json({
        ok: true,
        kind,
        alert_created: false,
        max_temperature_c: maxTemperature,
        critical_threshold_c: threshold,
      });
    }
  }

  const decision = classify(topic, values, threshold);
  if (!decision.shouldSurface) {
    return json({ ok: true, kind, alert_created: false, classification: decision.category });
  }

  const metric = `camera:${camera.device_uid}:${decision.category}`;
  const title = `${cameraName} — ${decision.title}`;

  const { data: exactDuplicate } = await admin
    .from("alerts")
    .select("id")
    .eq("farm_id", gateway.farm_id)
    .eq("source", "camera")
    .eq("metric", metric)
    .eq("created_at", eventTime)
    .limit(1);

  if (exactDuplicate && exactDuplicate.length > 0) {
    return json({ ok: true, kind, alert_created: false, duplicate: true, alert_id: exactDuplicate[0].id });
  }

  const throttleSince = new Date(Date.now() - 20_000).toISOString();
  const { data: throttled } = await admin
    .from("alerts")
    .select("id")
    .eq("farm_id", gateway.farm_id)
    .eq("source", "camera")
    .eq("metric", metric)
    .eq("title", title)
    .gte("created_at", throttleSince)
    .order("created_at", { ascending: false })
    .limit(1);

  if (throttled && throttled.length > 0) {
    return json({ ok: true, kind, alert_created: false, throttled: true, alert_id: throttled[0].id });
  }

  const operation = String(body?.operation ?? "").trim();
  const details = [
    `Camera: ${cameraName}`,
    `Gateway: ${gatewayUid}`,
    `Topic: ${topic}`,
    operation ? `Operation: ${operation}` : null,
    Object.keys(values).length
      ? Object.entries(values).map(([k, v]) => `${k}=${v}`).join(" • ")
      : null,
  ].filter(Boolean).join("\n");

  const { data: inserted, error: insertError } = await admin
    .from("alerts")
    .insert({
      farm_id: gateway.farm_id,
      risk: decision.risk,
      title,
      details,
      source: "camera",
      metric,
      value_numeric: decision.temperatureC,
      threshold_text: topic,
      created_at: eventTime,
    })
    .select("id,created_at")
    .single();

  if (insertError) return json({ error: insertError.message }, 500);

  await admin
    .from("camera_gateway_status")
    .update({ last_event_at: now, updated_at: now })
    .eq("gateway_device_id", gateway.id);

  await dispatchPush(inserted.id, key);

  return json({
    ok: true,
    kind,
    alert_created: true,
    alert_id: inserted.id,
    created_at: inserted.created_at,
    classification: decision.category,
    risk: decision.risk,
    critical_threshold_c: threshold,
  });
});
