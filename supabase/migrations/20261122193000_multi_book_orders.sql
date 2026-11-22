-- Multi-book orders: one order holds up to 5 books (one per child).
-- With 2+ books the cover charge (child name / «اتركه لذوقكم») is free for every book.

-- ---------- schema ----------
create table if not exists public.order_books (
  order_id uuid not null references public.orders(id) on delete cascade,
  book_no smallint not null check (book_no between 1 and 5),
  product_id uuid not null references public.products(id),
  child_name text check (char_length(child_name) <= 60),
  cover_mode public.cover_mode not null default 'manual',
  cover_config jsonb not null default '{}'::jsonb,
  gift_wrap boolean not null default false,
  lines jsonb not null default '[]'::jsonb,
  subtotal integer not null check (subtotal >= 0),
  primary key (order_id, book_no)
);
create index if not exists order_books_product_idx on public.order_books (product_id);
alter table public.order_books enable row level security;
drop policy if exists order_books_read on public.order_books;
create policy order_books_read on public.order_books for select to authenticated
  using ((select public.is_admin()) or exists (
    select 1 from public.orders o where o.id = order_id and o.guest_uid = (select auth.uid())));

alter table public.order_pages add column if not exists book_no smallint not null default 1;
alter table public.order_pages drop constraint if exists order_pages_pkey;
alter table public.order_pages add constraint order_pages_pkey primary key (order_id, book_no, page_number);

alter table public.orders add column if not exists book_count smallint not null default 1;
-- orders.child_name now lists every child ("سارة، علي") for search, lists and email
alter table public.orders drop constraint if exists orders_child_name_check;
alter table public.orders add constraint orders_child_name_check check (char_length(child_name) <= 140);

-- ---------- submit_order ----------
-- p: {customer_name, phone, city, address, notes, books: [{product_slug, gift_wrap, cover, pages}]}
-- A payload without "books" is read as a single book (older app builds).
create or replace function public.submit_order(p jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid := (select auth.uid());
  st public.app_settings%rowtype;
  v_name text := btrim(coalesce(p->>'customer_name', ''));
  v_phone text := regexp_replace(coalesce(p->>'phone', ''), '[\s\-()]', '', 'g');
  v_books jsonb := coalesce(p->'books', jsonb_build_array(p));
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
begin
  if uid is null then raise exception 'not_authenticated' using errcode = '28000'; end if;
  if (select count(*) from public.orders o
       where o.guest_uid = uid and o.created_at > now() - interval '1 day') >= 3 then
    raise exception 'too_many_orders';
  end if;
  if jsonb_typeof(v_books) <> 'array' then raise exception 'invalid_books'; end if;
  v_n := jsonb_array_length(v_books);
  if v_n not between 1 and 5 then raise exception 'invalid_books'; end if;
  v_multi := v_n > 1;
  select * into st from public.app_settings where id;

  for bk, bno in select e.value, e.ordinality::int from jsonb_array_elements(v_books) with ordinality e loop
    select * into prod from public.products where slug = bk->>'product_slug' and is_active;
    if not found then raise exception 'product_not_found'; end if;

    v_gift := coalesce((bk->>'gift_wrap')::boolean, false);
    v_child := btrim(coalesce(bk->'cover'->>'child_name', ''));
    if char_length(v_child) > 20 then raise exception 'invalid_child_name'; end if;
    v_mode := coalesce(nullif(bk->'cover'->>'mode', ''), 'manual')::public.cover_mode;
    if v_mode = 'ai' then raise exception 'invalid_cover_mode'; end if;
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
    v_el := bk->'cover'->'element';
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
      v_unit := coalesce((st.prices->>k)::int, 0);
      b_lines := b_lines || case when v_multi
        then jsonb_build_object('key', k, 'unit', 0, 'qty', 1, 'free', true, 'list_unit', v_unit)
        else jsonb_build_object('key', k, 'unit', v_unit, 'qty', 1) end;
    end if;
    if v_filled > 0 then
      -- pro rata: prices.photos buys every frame of the book; rounded up to 250 IQD
      select coalesce(sum(jsonb_array_length(t.photo_slots)), 0) into v_total_slots
        from public.page_templates t where t.product_id = prod.id;
      v_full := coalesce((st.prices->>'photos')::int, 0);
      b_lines := b_lines || jsonb_build_object('key', 'photos', 'qty', 1, 'filled', v_filled,
        'unit', case when v_filled >= v_total_slots then v_full
                     else (ceil(v_full::numeric * v_filled / v_total_slots / 250) * 250)::int end);
    end if;
    if v_has_text then
      b_lines := b_lines || jsonb_build_object('key', 'printed_text',
        'unit', coalesce((st.prices->>'printed_text')::int, 0), 'qty', 1);
    end if;
    if v_gift then
      b_lines := b_lines || jsonb_build_object('key', 'gift_wrap',
        'unit', coalesce((st.prices->>'gift_wrap')::int, 0), 'qty', 1);
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

  -- deposit: percent of the total, rounded up to deposit_round, never above the total
  v_deposit := least(v_total,
    (ceil(v_total * st.deposit_percent / 100 / greatest(st.deposit_round, 1)) * greatest(st.deposit_round, 1))::int);

  insert into public.orders (guest_uid, customer_name, phone, city, address, product_id,
      child_name, cover_mode, cover_config, addons, price_snapshot, subtotal,
      deposit_percent, deposit_amount, total, notes, book_count)
  values (uid, v_name, v_phone, btrim(coalesce(p->>'city', '')), btrim(coalesce(p->>'address', '')),
      first_prod, nullif(array_to_string(v_children, '، '), ''), first_mode, first_cover,
      (select coalesce(jsonb_agg(l) filter (where l->>'key' <> 'book'), '[]'::jsonb)
         from jsonb_array_elements(v_all_lines) l),
      jsonb_build_object('lines', v_all_lines, 'books', v_n, 'currency', 'IQD', 'prices', st.prices),
      v_total, st.deposit_percent, v_deposit, v_total,
      nullif(left(btrim(coalesce(p->>'notes', '')), 500), ''), v_n)
  returning id, order_code into v_order_id, v_code;

  insert into public.order_books (order_id, book_no, product_id, child_name, cover_mode, cover_config,
      gift_wrap, lines, subtotal)
  select v_order_id, (b->>'book_no')::int, (b->>'product_id')::uuid, nullif(b->>'child_name', ''),
         (b->>'cover_mode')::public.cover_mode, b->'cover_config', (b->>'gift_wrap')::boolean,
         b->'lines', (b->>'subtotal')::int
    from jsonb_array_elements(v_books_out) b;

  insert into public.order_pages (order_id, book_no, page_number, template_id, slots, texts, printed_text, text_is_paid)
  select v_order_id, (x->>'book_no')::int, (x->>'page_number')::int, (x->>'template_id')::uuid,
         x->'slots', x->'texts',
         nullif((select string_agg(t.value #>> '{}', E'\n') from jsonb_each(x->'texts') t), ''),
         x->'texts' <> '{}'::jsonb
    from jsonb_array_elements(v_pages) x;

  return jsonb_build_object('order_id', v_order_id, 'order_code', v_code,
    'total', v_total, 'deposit_amount', v_deposit, 'deposit_percent', st.deposit_percent);
end $$;

-- each order page belongs to one of the order's books
alter table public.order_pages
  drop constraint if exists order_pages_book_fk;
alter table public.order_pages
  add constraint order_pages_book_fk foreign key (order_id, book_no)
  references public.order_books (order_id, book_no) on delete cascade;
