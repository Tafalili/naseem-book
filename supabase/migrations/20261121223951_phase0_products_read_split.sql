-- Anon cannot execute is_admin(); keep customer read to active products only,
-- and give admins a separate policy to see inactive products.
alter policy products_read on public.products to anon, authenticated using (is_active);
create policy products_read_admin on public.products for select to authenticated using ((select public.is_admin()));
