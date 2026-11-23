-- Customers can move and resize the child's name on the cover.
-- submit_order keeps a sanitised cover.name_pos {dx, dy, scale}; everything else is unchanged.

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
    -- where the customer moved / resized the child's name on the cover
    if v_cover_ok and v_child <> '' and jsonb_typeof(bk->'cover'->'name_pos') = 'object' then
      v_cover := v_cover || jsonb_build_object('name_pos', jsonb_build_object(
        'dx', least(greatest(coalesce((bk->'cover'->'name_pos'->>'dx')::numeric, 0), -1), 1),
        'dy', least(greatest(coalesce((bk->'cover'->'name_pos'->>'dy')::numeric, 0), -1), 1),
        'scale', least(greatest(coalesce((bk->'cover'->'name_pos'->>'scale')::numeric, 1), 0.5), 2.5)));
    end if;

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

