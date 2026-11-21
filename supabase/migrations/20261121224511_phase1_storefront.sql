-- ========== Products: storefront fields ==========
alter table public.products
  add column tagline text check (char_length(tagline) <= 140),
  add column cover_image_path text,                 -- path in "templates" bucket
  add column is_featured boolean not null default false,
  add column badge text check (char_length(badge) <= 24);  -- e.g. "الأكثر طلباً"

create index products_storefront_idx on public.products (is_active, is_featured desc, sort_order);

-- ========== Banners (home slider / ads) ==========
create table public.banners (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) <= 80),
  subtitle text check (char_length(subtitle) <= 160),
  image_path text,                                  -- path in "templates" bucket; null = gradient card
  theme text not null default 'sage' check (theme in ('sage','sand','sky')),
  cta_label text check (char_length(cta_label) <= 30),
  product_id uuid references public.products(id) on delete set null,
  external_url text check (external_url ~ '^https://'),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);
create index banners_live_idx on public.banners (is_active, sort_order);
create index banners_product_idx on public.banners (product_id);
create trigger banners_updated_at before update on public.banners
  for each row execute function public.tg_set_updated_at();

alter table public.banners enable row level security;

create policy banners_read_live on public.banners for select to anon, authenticated
  using (is_active
         and (starts_at is null or starts_at <= now())
         and (ends_at is null or ends_at > now()));
create policy banners_read_admin on public.banners for select to authenticated
  using ((select public.is_admin()));
create policy banners_admin_insert on public.banners for insert to authenticated
  with check ((select public.is_admin()));
create policy banners_admin_update on public.banners for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy banners_admin_delete on public.banners for delete to authenticated
  using ((select public.is_admin()));

-- ========== Seed (placeholder content; edited from admin in phase 5) ==========
update public.products
   set is_featured = true,
       tagline = 'أول ذكريات طفلك، في كتاب يُصنع باليد خصيصاً له',
       badge = 'الأكثر طلباً'
 where slug = 'naseem-classic';

insert into public.banners (title, subtitle, theme, cta_label, product_id, sort_order)
select 'كتاب نسيم', 'اجمعي صور سنته الأولى في كتاب مطبوع ومجلّد يدوياً', 'sage', 'صمّمي كتابك', id, 0
  from public.products where slug = 'naseem-classic';
insert into public.banners (title, subtitle, theme, cta_label, sort_order) values
  ('هدية لا تُنسى', 'تغليف هدية أنيق متوفر مع كل كتاب', 'sand', 'اكتشفي المزيد', 1),
  ('صورك بأمان', 'تُحذف صور طفلك تلقائياً بعد طباعة الكتاب', 'sky', null, 2);
