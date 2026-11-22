-- Pricing (user, 2026-11-22): plain book 20,000 IQD; child's name on the cover +2,000;
-- photos inside the book (up to 34) +5,000 flat; printed texts +2,000 flat.
-- The child's name becomes optional.
update public.products set base_price = 20000 where slug = 'naseem-classic';
update public.app_settings
   set prices = prices || jsonb_build_object('child_name', 2000, 'photos', 5000, 'printed_text', 2000)
 where id;

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
  v_has_photo boolean := false;
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
  if char_length(v_child) > 20 then raise exception 'invalid_child_name'; end if;
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

    if v_slots <> '{}'::jsonb then v_has_photo := true; end if;
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
  if v_child <> '' then
    v_lines := v_lines || jsonb_build_object('key', 'child_name',
      'unit', coalesce((st.prices->>'child_name')::int, 0), 'qty', 1);
  end if;
  if v_has_photo then
    v_lines := v_lines || jsonb_build_object('key', 'photos',
      'unit', coalesce((st.prices->>'photos')::int, 0), 'qty', 1);
  end if;
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
