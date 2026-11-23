// Hourly photo purge, called by the `photo-purge` pg_cron job (run_photo_purge()).
// Asks purge_plan() which customer photos and receipts are due, removes them
// through the Storage API, then marks the orders with purge_done().
// Auth: same shared secret header as order-events, checked inside the RPCs.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

type Plan = { orders: string[]; files: { bucket: string; name: string }[] };

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const secret = req.headers.get("x-order-events-secret") ?? "";
  if (!secret) return new Response("forbidden", { status: 403 });

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data, error } = await db.rpc("purge_plan", { p_secret: secret });
  if (error) {
    const forbidden = error.message.includes("forbidden");
    return new Response(forbidden ? "forbidden" : error.message, { status: forbidden ? 403 : 500 });
  }
  const plan = data as Plan;

  const byBucket = new Map<string, string[]>();
  for (const f of plan.files) byBucket.set(f.bucket, [...(byBucket.get(f.bucket) ?? []), f.name]);

  let removed = 0;
  const failures: string[] = [];
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += 100) {
      const chunk = names.slice(i, i + 100);
      const { data: gone, error: err } = await db.storage.from(bucket).remove(chunk);
      if (err) failures.push(`${bucket}: ${err.message}`);
      else removed += gone?.length ?? 0;
    }
  }

  // Only mark orders when every removal went through; otherwise retry next hour.
  let marked = 0;
  if (failures.length === 0 && plan.orders.length > 0) {
    const { data: n, error: err } = await db.rpc("purge_done", { p_secret: secret, p_orders: plan.orders });
    if (err) failures.push(`purge_done: ${err.message}`);
    else marked = n as number;
  }

  const body = JSON.stringify({ removed, marked, failures });
  console.log(body);
  return new Response(body, {
    status: failures.length ? 500 : 200,
    headers: { "content-type": "application/json" },
  });
});
