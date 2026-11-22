// Order events from the `orders_event_notify` trigger (pg_net):
//  - new order / receipt uploaded  -> Telegram message to the store owner
//  - any status change             -> Web Push to the customer's subscribed browsers
// Auth: shared secret header, checked against Vault through a service_role-only RPC.
import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import webpush from "npm:web-push@3.6.7";

const STATUS: Record<string, string> = {
  pending_deposit: "🧾 استلمنا طلبك",
  deposit_review: "💳 نراجع العربون",
  confirmed: "✅ تم تأكيد طلبك",
  designing: "🎨 نصمم كتابك",
  printing: "🖨️ قيد الطباعة والتجليد",
  shipped: "🚚 في الطريق إليك",
  delivered: "🎁 تم التسليم",
  cancelled: "❌ ملغي",
};

const ADDONS: Record<string, string> = {
  printed_text: "نص مطبوع",
  designer_cover: "الغلاف من تصميمنا",
  gift_wrap: "تغليف هدية",
  extra_copy: "نسخة إضافية",
};

const esc = (s: unknown) =>
  String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const iqd = (n: number) => `${Math.round(n).toLocaleString("en-US")} د.ع`;

type Order = {
  id: string;
  order_code: string;
  customer_name: string;
  phone: string;
  city: string;
  address: string;
  child_name: string | null;
  cover_mode: string;
  total: number;
  deposit_amount: number;
  status: string;
  receipt_path: string | null;
  notes: string | null;
  addons: { key: string; qty: number }[];
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  const { data: cfg } = await db.rpc("order_events_config", {
    p_secret: req.headers.get("x-order-events-secret") ?? "",
  });
  if (!cfg) return new Response("forbidden", { status: 403 });

  const { order_id, event, to } = await req.json();
  const { data: o } = await db
    .from("orders")
    .select(
      "id,order_code,customer_name,phone,city,address,child_name,cover_mode,total,deposit_amount,status,receipt_path,notes,addons",
    )
    .eq("id", order_id)
    .maybeSingle<Order>();
  if (!o) return new Response("not found", { status: 404 });

  const result: Record<string, unknown> = {};
  if (event === "created" || to === "deposit_review") {
    result.telegram = await notifyOwner(db, cfg.telegram_chat_id, o, event === "created");
  }
  if (event === "status") {
    result.push = await notifyCustomer(db, cfg, o);
  }
  return Response.json(result);
});

async function notifyOwner(
  db: ReturnType<typeof createClient>,
  chatId: string | null,
  o: Order,
  isNew: boolean,
) {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN");
  if (!token || !chatId) return "skipped: telegram not configured";

  const addons = (o.addons ?? [])
    .map((a) => (a.qty > 1 ? `${ADDONS[a.key] ?? a.key} × ${a.qty}` : ADDONS[a.key] ?? a.key))
    .join("، ");
  const lines = isNew
    ? [
      `🆕 <b>طلب جديد ${esc(o.order_code)}</b>`,
      `👶 ${esc(o.child_name)}`,
      `👤 ${esc(o.customer_name)} · <code>${esc(o.phone)}</code>`,
      `📍 ${esc(o.city)} · ${esc(o.address)}`,
      `🎨 الغلاف: ${o.cover_mode === "designer" ? "من تصميمنا" : "من تصميم الزبونة"}`,
      addons ? `➕ ${esc(addons)}` : "",
      `💰 الإجمالي ${iqd(o.total)} · العربون ${iqd(o.deposit_amount)}`,
      o.notes ? `📝 ${esc(o.notes)}` : "",
    ]
    : [
      `💳 <b>إيصال عربون للطلب ${esc(o.order_code)}</b>`,
      `👤 ${esc(o.customer_name)} · <code>${esc(o.phone)}</code>`,
      `💰 العربون المطلوب ${iqd(o.deposit_amount)}`,
    ];

  if (!isNew && o.receipt_path) {
    const { data } = await db.storage.from("receipts").createSignedUrl(o.receipt_path, 60 * 60 * 24 * 7);
    if (data?.signedUrl) lines.push(`🔗 <a href="${esc(data.signedUrl)}">عرض الإيصال</a> (صالح 7 أيام)`);
  }

  const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      chat_id: chatId,
      text: lines.filter(Boolean).join("\n"),
      parse_mode: "HTML",
      disable_web_page_preview: true,
    }),
  });
  return res.ok ? "sent" : `error ${res.status}`;
}

async function notifyCustomer(
  db: ReturnType<typeof createClient>,
  cfg: { vapid_public: string | null; vapid_private: string | null },
  o: Order,
) {
  if (!cfg.vapid_public || !cfg.vapid_private) return "skipped: vapid not configured";
  const { data: subs } = await db
    .from("push_subscriptions")
    .select("id,endpoint,keys")
    .eq("order_id", o.id);
  if (!subs?.length) return "no subscriptions";

  webpush.setVapidDetails(
    Deno.env.get("PUSH_SUBJECT") ?? "https://github.com/Tafalili/naseem-book",
    cfg.vapid_public,
    cfg.vapid_private,
  );
  const payload = JSON.stringify({
    title: `كتاب نسيم · طلب ${o.order_code}`,
    body: STATUS[o.status] ?? o.status,
    url: `/order/${o.order_code}`,
  });

  let sent = 0;
  for (const s of subs) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: s.keys }, payload, { TTL: 60 * 60 * 24 });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) await db.from("push_subscriptions").delete().eq("id", s.id);
    }
  }
  return `sent ${sent}/${subs.length}`;
}
