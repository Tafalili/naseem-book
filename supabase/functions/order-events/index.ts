// Order events from the `orders_event_notify` trigger (pg_net):
//  - new order / receipt uploaded  -> e-mail (Resend) + Web Push to the store admins
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

// Public site address (set the SITE_URL secret once the domain is live); links are omitted until then.
const SITE_URL = (Deno.env.get("SITE_URL") ?? "").replace(/\/$/, "");
const PUSH_SUBJECT = Deno.env.get("PUSH_SUBJECT") ?? "https://github.com/Tafalili/naseem-book";

const ADDONS: Record<string, string> = {
  child_name: "اسم الطفل على الغلاف",
  photos: "صور داخل الكتاب",
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
    result.owner = await notifyOwner(db, cfg, o, event === "created");
  }
  if (event === "status") {
    result.push = await notifyCustomer(db, cfg, o);
  }
  return Response.json(result);
});

async function notifyOwner(
  db: ReturnType<typeof createClient>,
  cfg: { vapid_public: string | null; vapid_private: string | null; notify_email: string | null },
  o: Order,
  isNew: boolean,
) {
  const out: Record<string, string> = {};
  const addons = (o.addons ?? [])
    .map((a) => (a.qty > 1 ? `${ADDONS[a.key] ?? a.key} × ${a.qty}` : ADDONS[a.key] ?? a.key))
    .join("، ");
  const adminUrl = `${SITE_URL}/admin/orders/${o.id}`;
  const title = isNew ? `طلب جديد ${o.order_code}` : `وصل عربون للطلب ${o.order_code}`;

  // 1) e-mail through Resend (filterable: fixed sender + subject prefix)
  const key = Deno.env.get("RESEND_API_KEY");
  if (!key || !cfg.notify_email) {
    out.email = "skipped: not configured";
  } else {
    const rows: [string, string][] = isNew
      ? [
        ["الطفل", o.child_name || "بدون اسم على الغلاف"],
        ["الزبون", `${o.customer_name} · ${o.phone}`],
        ["العنوان", `${o.city} · ${o.address}`],
        ["الغلاف", o.cover_mode === "designer" ? "من تصميمنا" : "من تصميم الزبون"],
        ["الإضافات", addons || "لا توجد"],
        ["الإجمالي", iqd(o.total)],
        ["العربون", iqd(o.deposit_amount)],
        ...(o.notes ? [["ملاحظات", o.notes] as [string, string]] : []),
      ]
      : [
        ["الزبون", `${o.customer_name} · ${o.phone}`],
        ["العربون المطلوب", iqd(o.deposit_amount)],
      ];
    let receiptLink = "";
    if (!isNew && o.receipt_path) {
      const { data } = await db.storage.from("receipts").createSignedUrl(o.receipt_path, 60 * 60 * 24 * 7);
      if (data?.signedUrl) {
        receiptLink = `<p><a href="${esc(data.signedUrl)}">عرض الوصل</a> (الرابط صالح 7 أيام)</p>`;
      }
    }
    const html = `<div dir="rtl" style="font-family:Tahoma,Arial,sans-serif;font-size:15px;color:#2b2b2b">
<h2 style="color:#4f7a6c">${esc(title)}</h2>
<table cellpadding="6" style="border-collapse:collapse">${
      rows.map(([k, v]) => `<tr><td style="color:#777">${esc(k)}</td><td><b>${esc(v)}</b></td></tr>`).join("")
    }</table>${receiptLink}
${SITE_URL ? `<p><a href="${esc(adminUrl)}" style="background:#6E9A8B;color:#fff;padding:10px 18px;border-radius:8px;text-decoration:none">فتح الطلب في لوحة الإدارة</a></p>` : ""}
</div>`;
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
      body: JSON.stringify({
        from: Deno.env.get("NOTIFY_FROM") ?? "كتاب نسيم <onboarding@resend.dev>",
        to: [cfg.notify_email],
        subject: `[كتاب نسيم] ${title}`,
        html,
      }),
    });
    out.email = res.ok ? "sent" : `error ${res.status} ${await res.text()}`;
  }

  // 2) Web Push to every admin browser that enabled it
  if (!cfg.vapid_public || !cfg.vapid_private) {
    out.push = "skipped: vapid not configured";
  } else {
    const { data: subs } = await db.from("admin_push_subscriptions").select("id,endpoint,keys");
    webpush.setVapidDetails(PUSH_SUBJECT, cfg.vapid_public, cfg.vapid_private);
    const payload = JSON.stringify({
      title: `كتاب نسيم · ${title}`,
      body: isNew
        ? `${o.customer_name} · ${iqd(o.total)}`
        : `العربون ${iqd(o.deposit_amount)} · ${o.customer_name}`,
      url: `/admin/orders/${o.id}`,
    });
    out.push = await sendAll(db, "admin_push_subscriptions", subs ?? [], payload);
  }
  return out;
}

async function sendAll(
  db: ReturnType<typeof createClient>,
  table: string,
  subs: { id: string; endpoint: string; keys: { p256dh: string; auth: string } }[],
  payload: string,
) {
  if (!subs.length) return "no subscriptions";
  let sent = 0;
  for (const s of subs) {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: s.keys }, payload, { TTL: 60 * 60 * 24 });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) await db.from(table).delete().eq("id", s.id);
    }
  }
  return `sent ${sent}/${subs.length}`;
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
  webpush.setVapidDetails(PUSH_SUBJECT, cfg.vapid_public, cfg.vapid_private);
  const payload = JSON.stringify({
    title: `كتاب نسيم · طلب ${o.order_code}`,
    body: STATUS[o.status] ?? o.status,
    url: `/order/${o.order_code}`,
  });
  return await sendAll(db, "push_subscriptions", subs ?? [], payload);
}
