-- Shop: products of kind 'item' (frames, cards, tags...) sold with or without books in one order.
-- products.options = {min_qty, max_qty, unit_label, fields:[{id,label,type:text|longtext|date|time|photos,required,max,min,hint}]}
-- Books may override store prices with specs.prices and turn off cover options with specs.cover_custom=false.

alter table public.products add column if not exists kind text not null default 'book';
alter table public.products drop constraint if exists products_kind_check;
alter table public.products add constraint products_kind_check check (kind in ('book', 'item'));
alter table public.products add column if not exists options jsonb not null default '{}'::jsonb;

create table if not exists public.order_items (
  order_id uuid not null references public.orders(id) on delete cascade,
  item_no smallint not null check (item_no between 1 and 30),
  product_id uuid not null references public.products(id),
  qty integer not null check (qty between 1 and 1000),
  unit integer not null check (unit >= 0),
  fields jsonb not null default '{}'::jsonb,
  photos jsonb not null default '[]'::jsonb,
  subtotal integer not null check (subtotal >= 0),
  primary key (order_id, item_no)
);
create index if not exists order_items_product_idx on public.order_items (product_id);
alter table public.order_items enable row level security;
drop policy if exists order_items_read on public.order_items;
create policy order_items_read on public.order_items for select to authenticated
  using ((select public.is_admin()) or exists (
    select 1 from public.orders o where o.id = order_id and o.guest_uid = (select auth.uid())));

alter table public.orders add column if not exists item_count smallint not null default 0;

-- ---------- submit_order ----------
-- p: {customer_name, phone, city, address, notes,
--     books: [{product_slug, gift_wrap, cover, pages}], items: [{product_slug, qty, fields}]}
-- A payload with neither "books" nor "items" is read as a single book (older app builds).
create or replace function public.submit_order(p jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  st public.app_settings%rowtype;
  v_name text := btrim(coalesce(p->>'customer_name', ''));
  v_phone text := regexp_replace(coalesce(p->>'phone', ''), '[\s\-()]', '', 'g');
  v_books jsonb := case when p ? 'books' or p ? 'items' then coalesce(p->'books', '[]'::jsonb)
                        else jsonb_build_array(p) end;
  v_n int;
  v_multi boolean;
  bk jsonb;
  bno int;
  prod public.products%rowtype;
  first_prod uuid;
  v_mode public.cover_mode;
  first_mode public.cover_mode;
  first_cover jsonb;
  v_gift boolean;
  v_child text;
  v_children text[] := '{}';
  v_has_text boolean;
  v_filled int;
  v_total_slots int;
  v_full int;
  v_unit int;
  b_lines jsonb;
  b_sub int;
  v_all_lines jsonb := '[]'::jsonb;
  v_books_out jsonb := '[]'::jsonb;
  v_pages jsonb := '[]'::jsonb;
  v_total int := 0;
  v_deposit int;
  v_cover jsonb;
  v_el jsonb;
  v_order_id uuid;
  v_code text;
  pg jsonb;
  tpl public.page_templates%rowtype;
  k text;
  v jsonb;
  v_slots jsonb;
  v_texts jsonb;
  v_path text;
  n_pages int;
  v_items jsonb := coalesce(p->'items', '[]'::jsonb);
  v_items_out jsonb := '[]'::jsonb;
  it jsonb;
  ino int;
  v_qty int;
  v_minq int;
  v_maxq int;
  fld jsonb;
  fv jsonb;
  v_fields jsonb;
  v_photos jsonb;
  v_cnt int;
  v_pr jsonb;
  v_cover_ok boolean;
begin
  if uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if (select count(*) from public.orders o
       where o.guest_uid = uid and o.created_at > now() - interval '1 day') >= 3 then
    raise exception 'too_many_orders';
  end if;
  if jsonb_typeof(v_books) <> 'array' then raise exception 'invalid_books'; end if;
  v_n := jsonb_array_length(v_books);
  if v_n > 5 then raise exception 'invalid_books'; end if;
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) > 30 then raise exception 'invalid_items'; end if;
  if v_n + jsonb_array_length(v_items) = 0 then raise exception 'empty_order'; end if;
  v_multi := v_n > 1;
  select * into st from public.app_settings where id;

  for bk, bno in select e.value, e.ordinality::int from jsonb_array_elements(v_books) with ordinality e loop
    select * into prod from public.products where slug = bk->>'product_slug' and is_active and kind = 'book';
    if not found then raise exception 'product_not_found'; end if;
    -- per-book prices (specs.prices) override the store-wide ones; specs.cover_custom=false has no cover options
    v_pr := st.prices || coalesce(prod.specs->'prices', '{}'::jsonb);
    v_cover_ok := coalesce((prod.specs->>'cover_custom')::boolean, true);

    v_gift := coalesce((bk->>'gift_wrap')::boolean, false);
    v_child := btrim(coalesce(bk->'cover'->>'child_name', ''));
    if char_length(v_child) > 20 then raise exception 'invalid_child_name'; end if;
    v_mode := coalesce(nullif(bk->'cover'->>'mode', ''), 'manual')::public.cover_mode;
    if v_mode = 'ai' then raise exception 'invalid_cover_mode'; end if;
    if not v_cover_ok then
      v_child := '';
      v_mode := 'manual';
    end if;
    v_has_text := false;
    v_filled := 0;
    n_pages := 0;

    -- pages: validate every slot against the product's templates and the guest's own uploads
    for pg in select * from jsonb_array_elements(coalesce(bk->'pages', '[]'::jsonb)) loop
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

      v_filled := v_filled + (select count(*) from jsonb_object_keys(v_slots));
      if v_slots <> '{}'::jsonb or v_texts <> '{}'::jsonb then
        if exists (select 1 from jsonb_array_elements(v_pages) x
                    where (x->>'book_no')::int = bno and (x->>'page_number')::int = tpl.page_number) then
          raise exception 'invalid_page';
        end if;
        v_pages := v_pages || jsonb_build_object('book_no', bno,
          'page_number', tpl.page_number, 'template_id', tpl.id, 'slots', v_slots, 'texts', v_texts);
      end if;
    end loop;

    -- cover: keep only known keys
    v_el := case when v_cover_ok then bk->'cover'->'element' end;
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
      'font', left(coalesce(bk->'cover'->>'font', ''), 40),
      'color', (bk->'cover'->>'color')::bigint,
      'element', v_el,
      'designer_notes', left(btrim(coalesce(bk->'cover'->>'designer_notes', '')), 500));

    -- price: server-side, from app_settings (same rules as the app's estimate)
    b_lines := jsonb_build_array(jsonb_build_object('key', 'book', 'unit', prod.base_price, 'qty', 1));
    -- one cover charge per book; free for every book when the order has 2+ books
    if v_mode = 'designer' or v_child <> '' then
      k := case when v_mode = 'designer' then 'designer_cover' else 'child_name' end;
      v_unit := coalesce((v_pr->>k)::int, 0);
      b_lines := b_lines || case when v_multi
        then jsonb_build_object('key', k, 'unit', 0, 'qty', 1, 'free', true, 'list_unit', v_unit)
        else jsonb_build_object('key', k, 'unit', v_unit, 'qty', 1) end;
    end if;
    if v_filled > 0 then
      -- pro rata: prices.photos buys every frame of the book; rounded up to 250 IQD
      select coalesce(sum(jsonb_array_length(t.photo_slots)), 0) into v_total_slots
        from public.page_templates t where t.product_id = prod.id;
      v_full := coalesce((v_pr->>'photos')::int, 0);
      b_lines := b_lines || jsonb_build_object('key', 'photos', 'qty', 1, 'filled', v_filled,
        'unit', case when v_filled >= v_total_slots then v_full
                     else (ceil(v_full::numeric * v_filled / v_total_slots / 250) * 250)::int end);
    end if;
    if v_has_text then
      b_lines := b_lines || jsonb_build_object('key', 'printed_text',
        'unit', coalesce((v_pr->>'printed_text')::int, 0), 'qty', 1);
    end if;
    if v_gift then
      b_lines := b_lines || jsonb_build_object('key', 'gift_wrap',
        'unit', coalesce((v_pr->>'gift_wrap')::int, 0), 'qty', 1);
    end if;
    select coalesce(sum((l->>'unit')::int * (l->>'qty')::int), 0) into b_sub
      from jsonb_array_elements(b_lines) l;
    v_total := v_total + b_sub;

    v_all_lines := v_all_lines || (select jsonb_agg(l || jsonb_build_object('book_no', bno))
                                     from jsonb_array_elements(b_lines) l);
    v_books_out := v_books_out || jsonb_build_object('book_no', bno, 'product_id', prod.id,
      'child_name', v_child, 'cover_mode', v_mode, 'cover_config', v_cover,
      'gift_wrap', v_gift, 'lines', b_lines, 'subtotal', b_sub);
    if v_child <> '' then v_children := v_children || v_child; end if;
    if bno = 1 then first_prod := prod.id; first_mode := v_mode; first_cover := v_cover; end if;
  end loop;


  -- shop items: unit price from the product, quantity and fields checked against products.options
  for it, ino in select e.value, e.ordinality::int from jsonb_array_elements(v_items) with ordinality e loop
    select * into prod from public.products where slug = it->>'product_slug' and is_active and kind = 'item';
    if not found then raise exception 'product_not_found'; end if;
    v_minq := greatest(coalesce((prod.options->>'min_qty')::int, 1), 1);
    v_maxq := greatest(coalesce((prod.options->>'max_qty')::int, 99), v_minq);
    v_qty := coalesce((it->>'qty')::int, 0);
    if v_qty not between v_minq and v_maxq then raise exception 'invalid_qty'; end if;

    v_fields := '{}'::jsonb;
    v_photos := '[]'::jsonb;
    for fld in select * from jsonb_array_elements(coalesce(prod.options->'fields', '[]'::jsonb)) loop
      fv := it->'fields'->(fld->>'id');
      if fld->>'type' = 'photos' then
        v_cnt := case when jsonb_typeof(fv) = 'array' then jsonb_array_length(fv) else 0 end;
        if v_cnt > coalesce((fld->>'max')::int, 10)
           or (coalesce((fld->>'required')::boolean, false) and v_cnt < greatest(coalesce((fld->>'min')::int, 1), 1)) then
          raise exception 'invalid_item_photos';
        end if;
        for v in select * from jsonb_array_elements(coalesce(case when v_cnt > 0 then fv end, '[]'::jsonb)) loop
          v_path := v #>> '{}';
          if v_path is null or v_path not like uid::text || '/%'
             or not exists (select 1 from storage.objects o
                             where o.bucket_id = 'order-photos' and o.name = v_path) then
            raise exception 'invalid_photo';
          end if;
          v_photos := v_photos || to_jsonb(v_path);
        end loop;
        if v_cnt > 0 then v_fields := v_fields || jsonb_build_object(fld->>'id', fv); end if;
      else
        k := btrim(coalesce(case when jsonb_typeof(fv) = 'string' then fv #>> '{}' end, ''));
        if char_length(k) > coalesce((fld->>'max')::int, 60) then raise exception 'invalid_item_field'; end if;
        if k = '' and coalesce((fld->>'required')::boolean, false) then raise exception 'missing_item_field'; end if;
        if k <> '' then v_fields := v_fields || jsonb_build_object(fld->>'id', k); end if;
      end if;
    end loop;

    b_sub := prod.base_price * v_qty;
    v_total := v_total + b_sub;
    v_all_lines := v_all_lines || jsonb_build_object('key', prod.title, 'item_no', ino,
      'unit', prod.base_price, 'qty', v_qty);
    v_items_out := v_items_out || jsonb_build_object('item_no', ino, 'product_id', prod.id,
      'qty', v_qty, 'unit', prod.base_price, 'fields', v_fields, 'photos', v_photos, 'subtotal', b_sub);
    if first_prod is null then first_prod := prod.id; end if;
  end loop;

  -- deposit: percent of the total, rounded up to deposit_round, never above the total
  v_deposit := least(v_total,
    (ceil(v_total * st.deposit_percent / 100 / greatest(st.deposit_round, 1)) * greatest(st.deposit_round, 1))::int);

  insert into public.orders (guest_uid, customer_name, phone, city, address, product_id,
      child_name, cover_mode, cover_config, addons, price_snapshot, subtotal,
      deposit_percent, deposit_amount, total, notes, book_count, item_count)
  values (uid, v_name, v_phone, btrim(coalesce(p->>'city', '')), btrim(coalesce(p->>'address', '')),
      first_prod, nullif(array_to_string(v_children, '، '), ''), coalesce(first_mode, 'manual'), coalesce(first_cover, '{}'::jsonb),
      (select coalesce(jsonb_agg(l) filter (where l->>'key' <> 'book'), '[]'::jsonb)
         from jsonb_array_elements(v_all_lines) l),
      jsonb_build_object('lines', v_all_lines, 'books', v_n, 'items', jsonb_array_length(v_items_out),
        'currency', 'IQD', 'prices', st.prices),
      v_total, st.deposit_percent, v_deposit, v_total,
      nullif(left(btrim(coalesce(p->>'notes', '')), 500), ''), v_n, jsonb_array_length(v_items_out))
  returning id, order_code into v_order_id, v_code;

  insert into public.order_books (order_id, book_no, product_id, child_name, cover_mode, cover_config,
      gift_wrap, lines, subtotal)
  select v_order_id, (b->>'book_no')::int, (b->>'product_id')::uuid, nullif(b->>'child_name', ''),
         (b->>'cover_mode')::public.cover_mode, b->'cover_config', (b->>'gift_wrap')::boolean,
         b->'lines', (b->>'subtotal')::int
    from jsonb_array_elements(v_books_out) b;

  insert into public.order_items (order_id, item_no, product_id, qty, unit, fields, photos, subtotal)
  select v_order_id, (x->>'item_no')::int, (x->>'product_id')::uuid, (x->>'qty')::int, (x->>'unit')::int,
         x->'fields', x->'photos', (x->>'subtotal')::int
    from jsonb_array_elements(v_items_out) x;

  insert into public.order_pages (order_id, book_no, page_number, template_id, slots, texts, printed_text, text_is_paid)
  select v_order_id, (x->>'book_no')::int, (x->>'page_number')::int, (x->>'template_id')::uuid,
         x->'slots', x->'texts',
         nullif((select string_agg(t.value #>> '{}', E'\n') from jsonb_each(x->'texts') t), ''),
         x->'texts' <> '{}'::jsonb
    from jsonb_array_elements(v_pages) x;

  return jsonb_build_object('order_id', v_order_id, 'order_code', v_code,
    'total', v_total, 'deposit_amount', v_deposit, 'deposit_percent', st.deposit_percent);
end $$;


-- ---------- catalog ----------
insert into public.products (slug, title, description, tagline, base_price, page_count, photo_capacity,
    kind, options, cover_image_path, gallery, is_active, is_featured, sort_order)
values
  ('birth-frame', 'لوحة فريم المواليد',
   'لوحة مواليد بتصميم مميز تجمع صور طفلك مع تفاصيل يوم ولادته: الاسم والتاريخ والوقت والوزن والطول.',
   'ذكرى يوم الولادة في لوحة', 10000, 1, 1, 'item',
   '{"min_qty":1,"max_qty":10,"unit_label":"لوحة","fields":[
     {"id":"photos","label":"صور الطفل","type":"photos","required":true,"min":1,"max":20,"hint":"حتى 20 صورة"},
     {"id":"name","label":"اسم الطفل","type":"text","required":true,"max":30},
     {"id":"birth_date","label":"تاريخ الولادة","type":"date","required":true,"max":20},
     {"id":"birth_time","label":"وقت الولادة","type":"time","max":20},
     {"id":"weight","label":"الوزن","type":"text","max":20,"hint":"مثال: 3.5 كغم"},
     {"id":"length","label":"الطول","type":"text","max":20,"hint":"مثال: 50 سم"}]}',
   'asset:catalog/shop/birth-frame.webp', '[]', true, false, 10),
  ('dua-card', 'كارت الدعاء مع المسبحة',
   'كارت توزيعات بدعاء للمولود مع مسبحة صغيرة، يُطبع عليه اسم طفلك وصورته.',
   'توزيعات المولود', 1250, 1, 1, 'item',
   '{"min_qty":10,"max_qty":500,"unit_label":"قطعة","fields":[
     {"id":"name","label":"اسم الطفل","type":"text","required":true,"max":30},
     {"id":"photos","label":"صورة الطفل (اختياري)","type":"photos","max":1}]}',
   'asset:catalog/shop/dua-card.webp', '[]', true, false, 11),
  ('baqarah-pack', 'بكج سورة البقرة',
   'بكج كامل لحفظ سورة البقرة وقراءتها يومياً: كتاب سورة البقرة بحجم مناسب للحمل مع ملحقاته.',
   'رفيق يومي للقراءة', 30000, 1, 1, 'item',
   '{"min_qty":1,"max_qty":10,"unit_label":"بكج","fields":[
     {"id":"name","label":"الاسم على البكج (اختياري)","type":"text","max":30}]}',
   'asset:catalog/shop/baqarah-pack.webp', '[]', true, false, 12),
  ('hair-frame', 'فريم شعر المولود',
   'لوحة مميزة تحفظ أول خصلة من شعر طفلك مع رسمة واسمه.',
   'أول قصة شعر للذكرى', 15000, 1, 1, 'item',
   '{"min_qty":1,"max_qty":10,"unit_label":"فريم","fields":[
     {"id":"name","label":"اسم الطفل","type":"text","required":true,"max":30},
     {"id":"date","label":"التاريخ (اختياري)","type":"date","max":20}]}',
   'asset:catalog/shop/hair-frame.webp', '[]', true, false, 13),
  ('graduation-tags', 'تاكات التخرج',
   'تاكات توزيعات للتخرج بصورة طفلك واسمه وعبارة تختارها.',
   'توزيعات التخرج', 500, 1, 1, 'item',
   '{"min_qty":10,"max_qty":500,"unit_label":"قطعة","fields":[
     {"id":"photos","label":"صورة الطفل","type":"photos","required":true,"min":1,"max":1},
     {"id":"name","label":"اسم الطفل","type":"text","required":true,"max":30},
     {"id":"text","label":"العبارة","type":"text","max":40,"hint":"مثال: أميرتنا تخرجت"}]}',
   'asset:catalog/shop/graduation-tags.webp', '[]', true, false, 14)
on conflict (slug) do nothing;

-- ---------- «ذكرياتنا الحلوة»: friends memory book (18 pages, same 186x276 mm page as Naseem) ----------
-- Own add-on prices (photos 3,000 for every frame, pro rata; printed text 2,000) and no cover options.
insert into public.products (slug, title, description, tagline, base_price, page_count, photo_capacity,
    kind, specs, cover_image_path, gallery, is_active, is_featured, sort_order)
values ('friends-book', 'ذكرياتنا الحلوة',
  'كتاب ذكريات للصديقات: 18 صفحة لأول لقاء وأجمل المواقف والطلعات والوعود، تملئينها بصوركم وكلماتكم، ويُطبع ويُجلَّد يدوياً.',
  'كتاب ذكريات للصديقات', 15000, 18, 19, 'book',
  '{"dpi":300,"paper":"Matte 250gsm","trim_mm":{"w":186,"h":276},"bleed_mm":0,"cover_sheet":"A4","print_sheet":"A4","cover_white_stroke_mm":5,
    "endpaper_path":"asset:templates/naseem-classic/inside_cover.webp","back_cover_path":"asset:templates/naseem-classic/back_cover.webp",
    "prices":{"photos":3000,"printed_text":2000},"cover_custom":false}',
  'asset:catalog/friends-book/cover.webp',
  '["asset:catalog/friends-book/spread_1.webp","asset:catalog/friends-book/spread_2.webp","asset:catalog/friends-book/spread_3.webp","asset:catalog/friends-book/spread_4.webp"]',
  true, false, 1)
on conflict (slug) do nothing;

insert into public.page_templates (product_id, page_number, title, background_path, photo_slots, text_slots, is_cover)
select p.id, v.page_number, v.title, v.background_path, v.photo_slots, v.text_slots, v.is_cover
from public.products p
cross join (values
  (0, 'الغلاف', 'asset:templates/naseem-classic/cover_blank.webp', '[]'::jsonb, '[]'::jsonb, true),
  (1, 'ذكرياتنا الحلوة', 'asset:templates/friends-book/p01.webp', '[]'::jsonb, '[{"id": "ft1_1", "x": 47.67, "y": 178.8, "w": 84.92, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}]'::jsonb, false),
  (2, 'هذا الكتاب إلج', 'asset:templates/friends-book/p02.webp', '[{"id": "f2_1", "x": 61.69, "y": 172.9, "w": 68.9, "h": 53.81, "rotation": 2.6, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft2_1", "x": 44.7, "y": 77.03, "w": 102.7, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}, {"id": "ft2_2", "x": 44.7, "y": 97.43, "w": 102.62, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}, {"id": "ft2_3", "x": 44.7, "y": 117.5, "w": 102.62, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}]'::jsonb, false),
  (3, 'بداية حكايتنا', 'asset:templates/friends-book/p03.webp', '[{"id": "f3_1", "x": 57.83, "y": 115.31, "w": 100.96, "h": 112.22, "rotation": -2.0, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft3_1", "x": 18.71, "y": 53.66, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft3_2", "x": 18.71, "y": 79.65, "w": 143.09, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}]'::jsonb, false),
  (4, 'أول لقاء', 'asset:templates/friends-book/p04.webp', '[{"id": "f4_1", "x": 64.08, "y": 140.03, "w": 100.86, "h": 105.47, "rotation": 2.2, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft4_1", "x": 24.3, "y": 53.66, "w": 143.43, "h": 32.85, "rotation": 0, "kind": "memory", "lines": 4, "font_size_mm": 4.2}, {"id": "ft4_2", "x": 24.3, "y": 95.99, "w": 143.43, "h": 24.64, "rotation": 0, "kind": "memory", "lines": 3, "font_size_mm": 4.2}]'::jsonb, false),
  (5, 'أكثر موقف مضحك', 'asset:templates/friends-book/p05.webp', '[{"id": "f5_1", "x": 57.85, "y": 127.6, "w": 100.9, "h": 112.25, "rotation": -1.7, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft5_1", "x": 18.71, "y": 53.66, "w": 143.09, "h": 49.28, "rotation": 0, "kind": "memory", "lines": 6, "font_size_mm": 4.2}]'::jsonb, false),
  (6, 'أكثر موقف حزين', 'asset:templates/friends-book/p06.webp', '[{"id": "f6_1", "x": 64.04, "y": 127.54, "w": 100.87, "h": 112.41, "rotation": 1.9, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft6_1", "x": 24.38, "y": 53.66, "w": 143.34, "h": 49.28, "rotation": 0, "kind": "memory", "lines": 6, "font_size_mm": 4.2}]'::jsonb, false),
  (7, 'أكثر موقف سعيد', 'asset:templates/friends-book/p07.webp', '[{"id": "f7_1", "x": 57.87, "y": 127.62, "w": 101.0, "h": 112.32, "rotation": -2.2, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft7_1", "x": 18.71, "y": 53.66, "w": 143.09, "h": 49.28, "rotation": 0, "kind": "memory", "lines": 6, "font_size_mm": 4.2}]'::jsonb, false),
  (8, 'طلعاتنا معاً', 'asset:templates/friends-book/p08.webp', '[{"id": "f8_1", "x": 104.93, "y": 52.38, "w": 58.15, "h": 67.99, "rotation": 2.5, "shape": "rect", "radius": 0}, {"id": "f8_2", "x": 28.37, "y": 52.42, "w": 58.23, "h": 67.98, "rotation": -2.3, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft8_1", "x": 24.3, "y": 169.65, "w": 143.43, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}, {"id": "ft8_2", "x": 24.3, "y": 187.18, "w": 143.43, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}, {"id": "ft8_3", "x": 24.3, "y": 204.96, "w": 143.43, "h": 32.85, "rotation": 0, "kind": "memory", "lines": 4, "font_size_mm": 4.2}]'::jsonb, false),
  (9, 'صور من أيام زمان', 'asset:templates/friends-book/p09.webp', '[{"id": "f9_1", "x": 99.93, "y": 50.46, "w": 51.41, "h": 41.3, "rotation": 2.9, "shape": "rect", "radius": 0}, {"id": "f9_2", "x": 28.88, "y": 50.43, "w": 51.32, "h": 41.35, "rotation": -2.5, "shape": "rect", "radius": 0}, {"id": "f9_3", "x": 72.53, "y": 119.96, "w": 86.55, "h": 88.57, "rotation": 1.6, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft9_1", "x": 18.71, "y": 242.13, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}]'::jsonb, false),
  (10, 'أشياء لا يعرفها سوانا', 'asset:templates/friends-book/p10.webp', '[{"id": "f10_1", "x": 63.91, "y": 141.4, "w": 100.75, "h": 104.13, "rotation": -2.0, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft10_1", "x": 24.3, "y": 53.66, "w": 143.43, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft10_2", "x": 24.3, "y": 79.65, "w": 143.43, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft10_3", "x": 24.3, "y": 105.56, "w": 143.43, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}]'::jsonb, false),
  (11, 'أجمل صفات صديقتي', 'asset:templates/friends-book/p11.webp', '[{"id": "f11_1", "x": 58.18, "y": 141.5, "w": 101.0, "h": 103.88, "rotation": 2.0, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft11_1", "x": 18.71, "y": 53.66, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft11_2", "x": 18.71, "y": 79.65, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft11_3", "x": 18.71, "y": 105.56, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}]'::jsonb, false),
  (12, 'يومٌ لا يُنسى', 'asset:templates/friends-book/p12.webp', '[{"id": "f12_1", "x": 67.47, "y": 50.38, "w": 97.4, "h": 69.75, "rotation": -1.9, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft12_1", "x": 24.38, "y": 157.21, "w": 143.34, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}, {"id": "ft12_2", "x": 24.3, "y": 174.82, "w": 143.43, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}, {"id": "ft12_3", "x": 24.3, "y": 192.51, "w": 143.43, "h": 32.85, "rotation": 0, "kind": "memory", "lines": 4, "font_size_mm": 4.2}]'::jsonb, false),
  (13, 'أغانٍ وأماكن تذكّرنا ببعض', 'asset:templates/friends-book/p13.webp', '[{"id": "f13_1", "x": 57.99, "y": 141.4, "w": 100.83, "h": 104.09, "rotation": -1.9, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft13_1", "x": 18.71, "y": 53.66, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft13_2", "x": 18.71, "y": 79.65, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft13_3", "x": 18.71, "y": 105.56, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}]'::jsonb, false),
  (14, 'أحلامنا القادمة', 'asset:templates/friends-book/p14.webp', '[{"id": "f14_1", "x": 64.1, "y": 149.63, "w": 100.92, "h": 95.88, "rotation": 1.9, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft14_1", "x": 24.3, "y": 53.66, "w": 143.43, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft14_2", "x": 24.3, "y": 79.65, "w": 143.43, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}, {"id": "ft14_3", "x": 24.3, "y": 105.56, "w": 143.43, "h": 24.64, "rotation": 0, "kind": "memory", "lines": 3, "font_size_mm": 4.2}]'::jsonb, false),
  (15, 'وعدٌ بين الصديقات', 'asset:templates/friends-book/p15.webp', '[{"id": "f15_1", "x": 57.83, "y": 149.56, "w": 101.11, "h": 95.87, "rotation": -2.0, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft15_1", "x": 18.71, "y": 53.66, "w": 143.09, "h": 24.64, "rotation": 0, "kind": "memory", "lines": 3, "font_size_mm": 4.2}, {"id": "ft15_2", "x": 18.71, "y": 87.78, "w": 143.09, "h": 24.64, "rotation": 0, "kind": "memory", "lines": 3, "font_size_mm": 4.2}, {"id": "ft15_3", "x": 18.71, "y": 121.73, "w": 143.09, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}]'::jsonb, false),
  (16, 'رسالة من القلب إلى صديقتي', 'asset:templates/friends-book/p16.webp', '[]'::jsonb, '[{"id": "ft16_1", "x": 24.3, "y": 68.9, "w": 143.43, "h": 147.83, "rotation": 0, "kind": "memory", "lines": 18, "font_size_mm": 4.2}, {"id": "ft16_2", "x": 24.3, "y": 218.76, "w": 135.21, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}]'::jsonb, false),
  (17, 'أجمل صورة لنا', 'asset:templates/friends-book/p17.webp', '[{"id": "f17_1", "x": 56.37, "y": 58.55, "w": 102.42, "h": 112.3, "rotation": -1.4, "shape": "rect", "radius": 0}]'::jsonb, '[{"id": "ft17_1", "x": 18.71, "y": 214.1, "w": 143.09, "h": 8.21, "rotation": 0, "kind": "memory", "lines": 1, "font_size_mm": 4.2}, {"id": "ft17_2", "x": 18.71, "y": 231.88, "w": 143.09, "h": 16.43, "rotation": 0, "kind": "memory", "lines": 2, "font_size_mm": 4.2}]'::jsonb, false),
  (18, 'والحكاية… بعدها مستمرة', 'asset:templates/friends-book/p18.webp', '[{"id": "f18_1", "x": 54.44, "y": 130.13, "w": 83.65, "h": 61.64, "rotation": 1.9, "shape": "rect", "radius": 0}]'::jsonb, '[]'::jsonb, false)
) as v(page_number, title, background_path, photo_slots, text_slots, is_cover)
where p.slug = 'friends-book'
on conflict (product_id, page_number) do nothing;
