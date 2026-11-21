-- ========== Types ==========
create type public.order_status as enum (
  'pending_deposit','deposit_review','confirmed','designing',
  'printing','shipped','delivered','cancelled'
);
create type public.cover_mode as enum ('manual','ai','designer');
create type public.admin_role as enum ('owner','staff');

-- ========== Admins + role helpers ==========
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role public.admin_role not null default 'staff',
  display_name text,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.admins a where a.user_id = (select auth.uid())) $$;

create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.admins a where a.user_id = (select auth.uid()) and a.role = 'owner') $$;

revoke all on function public.is_admin() from public, anon;
revoke all on function public.is_owner() from public, anon;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_owner() to authenticated;

-- ========== Generic updated_at ==========
create or replace function public.tg_set_updated_at()
returns trigger language plpgsql set search_path = ''
as $$ begin new.updated_at = now(); return new; end $$;

-- ========== Products ==========
create table public.products (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  description text,
  base_price integer not null default 0 check (base_price >= 0),  -- IQD
  page_count integer not null default 34 check (page_count > 0),
  photo_capacity integer not null default 36 check (photo_capacity > 0),
  specs jsonb not null default '{}'::jsonb,
  gallery jsonb not null default '[]'::jsonb,                     -- array of storage paths in "templates"
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger products_updated_at before update on public.products
  for each row execute function public.tg_set_updated_at();

-- ========== Page templates (coords in mm, relative to trim box) ==========
create table public.page_templates (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  page_number integer not null check (page_number >= 0),          -- 0 = cover
  title text,
  background_path text,                                            -- path in "templates" bucket
  photo_slots jsonb not null default '[]'::jsonb,                  -- [{id,x,y,w,h,rotation,radius}]
  text_slots jsonb not null default '[]'::jsonb,                   -- [{id,x,y,w,h,font,size,color,align,lines}]
  is_cover boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, page_number)
);
create trigger page_templates_updated_at before update on public.page_templates
  for each row execute function public.tg_set_updated_at();

-- ========== App settings (singleton) ==========
create table public.app_settings (
  id boolean primary key default true check (id),
  prices jsonb not null default '{}'::jsonb,                      -- {"printed_text":0,"designer_cover":0,...} IQD
  deposit_percent numeric(5,2) not null default 50 check (deposit_percent between 0 and 100),
  purge_after_print_hours integer not null default 48 check (purge_after_print_hours > 0),
  purge_max_days integer not null default 14 check (purge_max_days > 0),
  wallets jsonb not null default '{}'::jsonb,                     -- {"zaincash":"","qicard":"","fib":""}
  enabled_fonts jsonb not null default '[]'::jsonb,
  cover_symbols jsonb not null default '[]'::jsonb,
  telegram_chat_id text,
  updated_at timestamptz not null default now()
);
create trigger app_settings_updated_at before update on public.app_settings
  for each row execute function public.tg_set_updated_at();

-- ========== Orders ==========
create or replace function public.gen_order_code()
returns text language plpgsql volatile set search_path = ''
as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  code text;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    exit when not exists (select 1 from public.orders o where o.order_code = code);
  end loop;
  return code;
end $$;

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_code text not null unique,
  guest_uid uuid not null references auth.users(id) on delete restrict,
  customer_name text not null check (char_length(customer_name) between 2 and 100),
  phone text not null check (phone ~ '^\+?[0-9]{10,15}$'),
  city text not null check (char_length(city) between 2 and 60),
  address text not null check (char_length(address) between 3 and 300),
  product_id uuid not null references public.products(id),
  child_name text check (char_length(child_name) <= 60),
  cover_mode public.cover_mode not null default 'manual',
  cover_config jsonb not null default '{}'::jsonb,
  addons jsonb not null default '[]'::jsonb,
  price_snapshot jsonb not null default '{}'::jsonb,
  subtotal integer not null check (subtotal >= 0),
  deposit_percent numeric(5,2) not null check (deposit_percent between 0 and 100),
  deposit_amount integer not null check (deposit_amount >= 0),
  total integer not null check (total >= 0),
  receipt_path text,
  status public.order_status not null default 'pending_deposit',
  printed_at timestamptz,
  images_purged_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.orders alter column order_code set default public.gen_order_code();
create index orders_guest_uid_idx on public.orders (guest_uid);
create index orders_status_idx on public.orders (status, created_at desc);
create index orders_product_idx on public.orders (product_id);
create trigger orders_updated_at before update on public.orders
  for each row execute function public.tg_set_updated_at();

-- ========== Order pages ==========
create table public.order_pages (
  order_id uuid not null references public.orders(id) on delete cascade,
  page_number integer not null check (page_number >= 0),
  template_id uuid references public.page_templates(id) on delete set null,
  photo_path text,                                                 -- order-photos/{uid}/...
  transform jsonb not null default '{"scale":1,"offsetX":0,"offsetY":0}'::jsonb,
  printed_text text check (char_length(printed_text) <= 500),
  text_is_paid boolean not null default false,
  primary key (order_id, page_number)
);
create index order_pages_template_idx on public.order_pages (template_id);

-- ========== Status history (timeline) ==========
create table public.order_status_history (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  from_status public.order_status,
  to_status public.order_status not null,
  changed_by uuid references auth.users(id) on delete set null,
  note text check (char_length(note) <= 500),
  at timestamptz not null default now()
);
create index order_status_history_order_idx on public.order_status_history (order_id, at);
create index order_status_history_changed_by_idx on public.order_status_history (changed_by);

create or replace function public.tg_log_order_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by)
    values (new.id, null, new.status, (select auth.uid()));
  elsif new.status is distinct from old.status then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by, note)
    values (new.id, old.status, new.status, (select auth.uid()),
            nullif(current_setting('app.status_note', true), ''));
  end if;
  return new;
end $$;
revoke all on function public.tg_log_order_status() from public, anon, authenticated;
create trigger orders_status_log after insert or update of status on public.orders
  for each row execute function public.tg_log_order_status();

-- ========== Push subscriptions ==========
create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  guest_uid uuid not null references auth.users(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  endpoint text not null,
  keys jsonb not null,
  created_at timestamptz not null default now(),
  unique (order_id, endpoint)
);
create index push_subscriptions_guest_idx on public.push_subscriptions (guest_uid);

-- ========== RLS ==========
alter table public.admins enable row level security;
alter table public.products enable row level security;
alter table public.page_templates enable row level security;
alter table public.app_settings enable row level security;
alter table public.orders enable row level security;
alter table public.order_pages enable row level security;
alter table public.order_status_history enable row level security;
alter table public.push_subscriptions enable row level security;

-- admins: each admin sees own row; owner manages all
create policy admins_select on public.admins for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_owner()));
create policy admins_owner_write on public.admins for all to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));

-- products / templates: public read (active only for non-admins), admin write
create policy products_read on public.products for select to anon, authenticated
  using (is_active or (select public.is_admin()));
create policy products_admin_insert on public.products for insert to authenticated
  with check ((select public.is_admin()));
create policy products_admin_update on public.products for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy products_admin_delete on public.products for delete to authenticated
  using ((select public.is_admin()));

create policy templates_read on public.page_templates for select to anon, authenticated using (true);
create policy templates_admin_insert on public.page_templates for insert to authenticated
  with check ((select public.is_admin()));
create policy templates_admin_update on public.page_templates for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy templates_admin_delete on public.page_templates for delete to authenticated
  using ((select public.is_admin()));

-- app_settings: admins read, owner writes; public data via RPC below
create policy settings_admin_read on public.app_settings for select to authenticated
  using ((select public.is_admin()));
create policy settings_owner_update on public.app_settings for update to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));

-- orders: guest reads own; no direct insert (submit_order RPC, phase 4); admins read/update
create policy orders_read on public.orders for select to authenticated
  using (guest_uid = (select auth.uid()) or (select public.is_admin()));
create policy orders_admin_update on public.orders for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy orders_owner_delete on public.orders for delete to authenticated
  using ((select public.is_owner()));

create policy order_pages_read on public.order_pages for select to authenticated
  using ((select public.is_admin()) or exists (
    select 1 from public.orders o where o.id = order_id and o.guest_uid = (select auth.uid())));
create policy order_pages_admin_update on public.order_pages for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

create policy history_read on public.order_status_history for select to authenticated
  using ((select public.is_admin()) or exists (
    select 1 from public.orders o where o.id = order_id and o.guest_uid = (select auth.uid())));

create policy push_own_read on public.push_subscriptions for select to authenticated
  using (guest_uid = (select auth.uid()) or (select public.is_admin()));
create policy push_own_insert on public.push_subscriptions for insert to authenticated
  with check (guest_uid = (select auth.uid()) and exists (
    select 1 from public.orders o where o.id = order_id and o.guest_uid = (select auth.uid())));
create policy push_own_delete on public.push_subscriptions for delete to authenticated
  using (guest_uid = (select auth.uid()));

-- ========== Public RPCs ==========
create or replace function public.get_public_settings()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'prices', s.prices,
    'deposit_percent', s.deposit_percent,
    'enabled_fonts', s.enabled_fonts,
    'cover_symbols', s.cover_symbols,
    'purge_after_print_hours', s.purge_after_print_hours,
    'purge_max_days', s.purge_max_days)
  from public.app_settings s where s.id
$$;
grant execute on function public.get_public_settings() to anon, authenticated;

-- wallets only for a guest who has an order awaiting deposit, or admins
create or replace function public.get_payment_wallets()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select s.wallets from public.app_settings s
  where s.id and (
    exists (select 1 from public.orders o
            where o.guest_uid = (select auth.uid()) and o.status in ('pending_deposit','deposit_review'))
    or exists (select 1 from public.admins a where a.user_id = (select auth.uid())))
$$;
revoke all on function public.get_payment_wallets() from public, anon;
grant execute on function public.get_payment_wallets() to authenticated;

revoke all on function public.gen_order_code() from public, anon, authenticated;

-- ========== Seed ==========
insert into public.app_settings (id, prices, wallets, enabled_fonts)
values (true,
  '{"printed_text":0,"designer_cover":0,"ai_cover":0,"smart_manuscript":0,"gift_wrap":0,"extra_copy":0}'::jsonb,
  '{"zaincash":"","qicard":"","fib":""}'::jsonb,
  '["Thuluth","Naskh","Kufi"]'::jsonb);

insert into public.products (slug, title, description, base_price, page_count, photo_capacity, specs)
values ('naseem-classic', 'كتاب نسيم', 'كتاب ذكريات طفلك الأولى بتصميم يناسب الأولاد والبنات', 0, 34, 36,
  '{"trim_mm":{"w":185.5,"h":274.5},"bleed_mm":3,"paper":"Matte 250gsm","dpi":300}'::jsonb);
