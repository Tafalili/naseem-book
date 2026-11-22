-- Phase 4: order submission, receipt, tracking, event notifications.
create extension if not exists pg_net with schema extensions;

-- A page can hold several frames: per-slot placements and printed texts.
alter table public.order_pages
  add column if not exists slots jsonb not null default '{}'::jsonb,  -- {slotId:{photo_path,scale,dx,dy}}
  add column if not exists texts jsonb not null default '{}'::jsonb;  -- {textSlotId:"..."}
alter table public.orders
  add column if not exists notes text check (char_length(notes) <= 500);

-- ---------- submit_order ----------
create or replace function public.submit_order(p jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  prod public.products%rowtype;
  st public.app_settings%rowtype;
  v_mode public.cover_mode;
  v_gift boolean := coalesce((p->>'gift_wrap')::boolean, false);
  v_copies int := coalesce((p->>'extra_copies')::int, 0);
  v_name text := btrim(coalesce(p->>'customer_name', ''));
  v_phone text := regexp_replace(coalesce(p->>'phone', ''), '[\s\-()]', '', 'g');
  v_child text := btrim(coalesce(p->'cover'->>'child_name', ''));
  v_has_text boolean := false;
  v_lines jsonb := '[]'::jsonb;
  v_total int;
  v_deposit int;
  v_cover jsonb;
  v_el jsonb;
  v_order_id uuid;
  v_code text;
  pg jsonb;
  tpl public.page_templates%rowtype;
  k text;
  v jsonb;
  v_pages jsonb := '[]'::jsonb;
  v_slots jsonb;
  v_texts jsonb;
  v_path text;
  n_pages int := 0;
begin
  if uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if (select count(*) from public.orders o
       where o.guest_uid = uid and o.created_at > now() - interval '1 day') >= 3 then
    raise exception 'too_many_orders';
  end if;

  select * into prod from public.products where slug = p->>'product_slug' and is_active;
  if not found then raise exception 'product_not_found'; end if;
  select * into st from public.app_settings where id;

  if v_copies not between 0 and 5 then raise exception 'invalid_extra_copies'; end if;
  if char_length(v_child) not between 1 and 20 then raise exception 'invalid_child_name'; end if;
  v_mode := coalesce(nullif(p->'cover'->>'mode', ''), 'manual')::public.cover_mode;
  if v_mode = 'ai' then raise exception 'invalid_cover_mode'; end if;

  -- pages: validate every slot against the product's templates and the guest's own uploads
  for pg in select * from jsonb_array_elements(coalesce(p->'pages', '[]'::jsonb)) loop
    n_pages := n_pages + 1;
    if n_pages > 100 then raise exception 'too_many_pages'; end if;
    select * into tpl from public.page_templates t
     where t.product_id = prod.id and t.page_number = (pg->>'page_number')::int;
    if not found then raise exception 'invalid_page'; end if;

    v_slots := '{}'::jsonb;
    for k, v in select * from jsonb_each(coalesce(pg->'slots', '{}'::jsonb)) loop
      if not exists (select 1 from jsonb_array_elements(tpl.photo_slots) s where s->>'id' = k) then
        raise exception 'invalid_slot';
      end if;
      v_path := v->>'photo_path';
      if v_path is null or v_path not like uid::text || '/%'
         or not exists (select 1 from storage.objects o
                         where o.bucket_id = 'order-photos' and o.name = v_path) then
        raise exception 'invalid_photo';
      end if;
      v_slots := v_slots || jsonb_build_object(k, jsonb_build_object(
        'photo_path', v_path,
        'scale', least(greatest(coalesce((v->>'scale')::numeric, 1), 1), 4),
        'dx', least(greatest(coalesce((v->>'dx')::numeric, 0), -2), 2),
        'dy', least(greatest(coalesce((v->>'dy')::numeric, 0), -2), 2)));
    end loop;

    v_texts := '{}'::jsonb;
    for k, v in select * from jsonb_each(coalesce(pg->'texts', '{}'::jsonb)) loop
      if not exists (select 1 from jsonb_array_elements(tpl.text_slots) s
                      where s->>'id' = k and s->>'kind' = 'memory') then
        raise exception 'invalid_text_slot';
      end if;
      if jsonb_typeof(v) <> 'string' or char_length(v #>> '{}') > 500 then
        raise exception 'invalid_text';
      end if;
      if btrim(v #>> '{}') <> '' then
        v_texts := v_texts || jsonb_build_object(k, btrim(v #>> '{}'));
        v_has_text := true;
      end if;
    end loop;

    if v_slots <> '{}'::jsonb or v_texts <> '{}'::jsonb then
      v_pages := v_pages || jsonb_build_object(
        'page_number', tpl.page_number, 'template_id', tpl.id, 'slots', v_slots, 'texts', v_texts);
    end if;
  end loop;

  -- cover: keep only known keys
  v_el := p->'cover'->'element';
  if v_el is not null and jsonb_typeof(v_el) = 'object' then
    v_path := v_el->>'photo_path';
    if v_path is null or v_path not like uid::text || '/%'
       or not exists (select 1 from storage.objects o
                       where o.bucket_id = 'order-photos' and o.name = v_path) then
      raise exception 'invalid_photo';
    end if;
    v_el := jsonb_build_object(
      'photo_path', v_path,
      'cx', (v_el->>'cx')::numeric, 'cy', (v_el->>'cy')::numeric,
      'width', (v_el->>'width')::numeric, 'rotation', (v_el->>'rotation')::numeric);
  else
    v_el := null;
  end if;
  v_cover := jsonb_build_object(
    'mode', v_mode,
    'child_name', v_child,
    'font', left(coalesce(p->'cover'->>'font', ''), 40),
    'color', (p->'cover'->>'color')::bigint,
    'element', v_el,
    'designer_notes', left(btrim(coalesce(p->'cover'->>'designer_notes', '')), 500));

  -- price: server-side, from app_settings (same rules as the app's estimate)
  v_lines := jsonb_build_array(jsonb_build_object('key', 'book', 'unit', prod.base_price, 'qty', 1));
  if v_has_text then
    v_lines := v_lines || jsonb_build_object('key', 'printed_text',
      'unit', coalesce((st.prices->>'printed_text')::int, 0), 'qty', 1);
  end if;
  if v_mode = 'designer' then
    v_lines := v_lines || jsonb_build_object('key', 'designer_cover',
      'unit', coalesce((st.prices->>'designer_cover')::int, 0), 'qty', 1);
  end if;
  if v_gift then
    v_lines := v_lines || jsonb_build_object('key', 'gift_wrap',
      'unit', coalesce((st.prices->>'gift_wrap')::int, 0), 'qty', 1);
  end if;
  if v_copies > 0 then
    v_lines := v_lines || jsonb_build_object('key', 'extra_copy',
      'unit', coalesce((st.prices->>'extra_copy')::int, 0), 'qty', v_copies);
  end if;
  select coalesce(sum((l->>'unit')::int * (l->>'qty')::int), 0) into v_total
    from jsonb_array_elements(v_lines) l;
  v_deposit := round(v_total * st.deposit_percent / 100);

  insert into public.orders (guest_uid, customer_name, phone, city, address, product_id,
      child_name, cover_mode, cover_config, addons, price_snapshot, subtotal,
      deposit_percent, deposit_amount, total, notes)
  values (uid, v_name, v_phone, btrim(coalesce(p->>'city', '')), btrim(coalesce(p->>'address', '')),
      prod.id, v_child, v_mode, v_cover,
      (select coalesce(jsonb_agg(l) filter (where l->>'key' <> 'book'), '[]'::jsonb)
         from jsonb_array_elements(v_lines) l),
      jsonb_build_object('lines', v_lines, 'currency', 'IQD', 'prices', st.prices),
      v_total, st.deposit_percent, v_deposit, v_total,
      nullif(left(btrim(coalesce(p->>'notes', '')), 500), ''))
  returning id, order_code into v_order_id, v_code;

  insert into public.order_pages (order_id, page_number, template_id, slots, texts, printed_text, text_is_paid)
  select v_order_id, (x->>'page_number')::int, (x->>'template_id')::uuid, x->'slots', x->'texts',
         nullif((select string_agg(t.value #>> '{}', E'\n') from jsonb_each(x->'texts') t), ''),
         x->'texts' <> '{}'::jsonb
    from jsonb_array_elements(v_pages) x;

  return jsonb_build_object('order_id', v_order_id, 'order_code', v_code,
    'total', v_total, 'deposit_amount', v_deposit, 'deposit_percent', st.deposit_percent);
end $$;
revoke all on function public.submit_order(jsonb) from public, anon;
grant execute on function public.submit_order(jsonb) to authenticated;

-- ---------- attach_receipt ----------
create or replace function public.attach_receipt(p_order_id uuid, p_path text)
returns void language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid());
begin
  if uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if p_path not like uid::text || '/%'
     or not exists (select 1 from storage.objects o where o.bucket_id = 'receipts' and o.name = p_path) then
    raise exception 'invalid_receipt';
  end if;
  update public.orders set receipt_path = p_path, status = 'deposit_review'
   where id = p_order_id and guest_uid = uid and status = 'pending_deposit';
  if not found then raise exception 'order_not_awaiting_deposit'; end if;
end $$;
revoke all on function public.attach_receipt(uuid, text) from public, anon;
grant execute on function public.attach_receipt(uuid, text) to authenticated;

-- ---------- track_order (any device: code + phone) ----------
create or replace function public.track_order(p_code text, p_phone text)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'order_code', o.order_code,
    'status', o.status,
    'child_name', o.child_name,
    'total', o.total,
    'deposit_amount', o.deposit_amount,
    'deposit_percent', o.deposit_percent,
    'created_at', o.created_at,
    'images_purged_at', o.images_purged_at,
    'history', coalesce((select jsonb_agg(jsonb_build_object('to_status', h.to_status, 'note', h.note, 'at', h.at)
                                          order by h.at)
                           from public.order_status_history h where h.order_id = o.id), '[]'::jsonb))
  from public.orders o
  where o.order_code = upper(btrim(p_code))
    and right(regexp_replace(o.phone, '\D', '', 'g'), 10) = right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10)
    and char_length(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')) >= 10
$$;
grant execute on function public.track_order(text, text) to anon, authenticated;

-- ---------- order events -> Edge Function (Telegram to owner, Web Push to guest) ----------
-- Secrets live in Vault (inserted outside migrations): order_events_secret, vapid_public, vapid_private.
create or replace function public.tg_order_event()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare secret text;
begin
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'order_events_secret';
  if secret is null then return new; end if;
  perform net.http_post(
    url := 'https://edarzlqkxgobdffcfnpx.supabase.co/functions/v1/order-events',
    body := jsonb_build_object(
      'order_id', new.id,
      'event', case when tg_op = 'INSERT' then 'created' else 'status' end,
      'from', case when tg_op = 'UPDATE' then old.status end,
      'to', new.status),
    headers := jsonb_build_object('content-type', 'application/json', 'x-order-events-secret', secret),
    timeout_milliseconds := 5000);
  return new;
end $$;
revoke all on function public.tg_order_event() from public, anon, authenticated;
create trigger orders_event_notify after insert or update of status on public.orders
  for each row execute function public.tg_order_event();

-- service_role only: the Edge Function checks the shared secret and reads push keys
create or replace function public.order_events_config(p_secret text)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select case when p_secret = (select decrypted_secret from vault.decrypted_secrets where name = 'order_events_secret')
    then jsonb_build_object(
      'vapid_public', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public'),
      'vapid_private', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_private'),
      'telegram_chat_id', (select s.telegram_chat_id from public.app_settings s where s.id))
  end
$$;
revoke all on function public.order_events_config(text) from public, anon, authenticated;
grant execute on function public.order_events_config(text) to service_role;
