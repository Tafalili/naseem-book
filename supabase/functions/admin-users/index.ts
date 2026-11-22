// Team management for the admin panel (owner only).
//   POST { action: "create", email, password, role: "owner"|"staff", display_name? }
//   POST { action: "remove", user_id }
// The caller's JWT is checked with is_owner(); user creation needs the service role.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const cors = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: me } = await caller.auth.getUser();
  const { data: isOwner } = await caller.rpc("is_owner");
  if (!me?.user || isOwner !== true) return json({ error: "forbidden" }, 403);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const body = await req.json().catch(() => ({}));

  if (body.action === "create") {
    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const role = body.role === "owner" ? "owner" : "staff";
    const name = String(body.display_name ?? "").trim().slice(0, 60) || null;
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "invalid_email" }, 400);
    if (password.length < 8) return json({ error: "weak_password" }, 400);

    const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true });
    if (error || !data.user) {
      const exists = /already|registered|exists/i.test(error?.message ?? "");
      return json({ error: exists ? "email_exists" : "create_failed" }, 400);
    }
    const { error: insErr } = await admin.from("admins").insert({ user_id: data.user.id, role, display_name: name });
    if (insErr) {
      await admin.auth.admin.deleteUser(data.user.id);
      return json({ error: "create_failed" }, 400);
    }
    return json({ user_id: data.user.id });
  }

  if (body.action === "remove") {
    const id = String(body.user_id ?? "");
    if (!id || id === me.user.id) return json({ error: "cannot_remove_self" }, 400);
    const { error } = await admin.auth.admin.deleteUser(id); // admins row cascades
    return error ? json({ error: "remove_failed" }, 400) : json({ ok: true });
  }

  return json({ error: "unknown_action" }, 400);
});
