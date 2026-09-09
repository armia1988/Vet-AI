import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: cors });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ ok: false, error: "POST required" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return json({ ok: false, error: "Missing authorization" }, 401);

  const scoped = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false },
  });
  const service = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userError } = await service.auth.getUser(jwt);
  if (userError || !userData.user) return json({ ok: false, error: "Invalid session" }, 401);

  const { data: allowed, error: permissionError } = await scoped.rpc("is_admin_account", {
    required_permission: "manage_admins",
  });
  if (permissionError || allowed !== true) return json({ ok: false, error: "Admin account permission required" }, 403);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) {}
  const action = String(body.action ?? "").trim();

  try {
    if (action === "list") {
      const users: Record<string, unknown>[] = [];
      for (let page = 1; page <= 20; page++) {
        const { data, error } = await service.auth.admin.listUsers({ page, perPage: 100 });
        if (error) throw error;
        for (const user of data.users) {
          users.push({
            id: user.id,
            email: user.email ?? null,
            email_confirmed_at: user.email_confirmed_at ?? null,
            last_sign_in_at: user.last_sign_in_at ?? null,
            created_at: user.created_at,
          });
        }
        if (data.users.length < 100) break;
      }
      return json({ ok: true, users });
    }

    if (action === "update") {
      const targetUserId = String(body.user_id ?? "").trim();
      if (!targetUserId) return json({ ok: false, error: "user_id required" }, 400);
      const attributes: Record<string, unknown> = {};
      if (typeof body.email === "string" && body.email.trim()) attributes.email = body.email.trim().toLowerCase();
      if (typeof body.password === "string" && body.password.trim()) {
        if (body.password.trim().length < 8) return json({ ok: false, error: "Password must be at least 8 characters" }, 400);
        attributes.password = body.password.trim();
      }
      if (Object.keys(attributes).length === 0) return json({ ok: false, error: "Nothing to update" }, 400);
      const { data, error } = await service.auth.admin.updateUserById(targetUserId, attributes);
      if (error) throw error;
      return json({ ok: true, user: { id: data.user.id, email: data.user.email ?? null } });
    }

    if (action === "create") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "").trim();
      const fullName = String(body.full_name ?? "").trim();
      const phone = String(body.phone ?? "").trim();
      const language = String(body.preferred_language ?? "en").trim() || "en";
      const kind = String(body.kind ?? "customer").trim();
      const permissions = (body.permissions && typeof body.permissions === "object") ? body.permissions : {};
      if (!email.includes("@")) return json({ ok: false, error: "Valid email required" }, 400);
      if (password.length < 8) return json({ ok: false, error: "Password must be at least 8 characters" }, 400);
      const allowedKinds = new Set(["customer", "manager", "assistant_manager", "admin", "support", "operations", "billing"]);
      if (!allowedKinds.has(kind)) return json({ ok: false, error: "Invalid account type" }, 400);

      const { data: created, error: createError } = await service.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, phone, preferred_language: language },
      });
      if (createError || !created.user) throw createError ?? new Error("User creation failed");
      const id = created.user.id;

      const { error: profileError } = await service.from("profiles").upsert({
        id,
        full_name: fullName || null,
        phone: phone || null,
        preferred_language: language,
        account_status: "active",
      });
      if (profileError) {
        await service.auth.admin.deleteUser(id);
        throw profileError;
      }

      if (kind !== "customer") {
        const { error: adminError } = await service.from("admin_accounts").upsert({
          user_id: id,
          role: kind,
          active: true,
          permissions,
        });
        if (adminError) {
          await service.from("profiles").delete().eq("id", id);
          await service.auth.admin.deleteUser(id);
          throw adminError;
        }
      }
      return json({ ok: true, user: { id, email }, kind });
    }

    return json({ ok: false, error: "Unknown action" }, 400);
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400);
  }
});
