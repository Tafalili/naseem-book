-- Phase 6: full-resolution print files (300 DPI page designs), private to the store team.
-- page_templates.print_path -> print-files/<product_slug>/<file>; the app's preview images stay small.

alter table public.page_templates add column if not exists print_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('print-files', 'print-files', false, 41943040, array['image/jpeg','image/png'])
on conflict (id) do nothing;

drop policy if exists print_files_admin_select on storage.objects;
create policy print_files_admin_select on storage.objects for select to authenticated
  using (bucket_id = 'print-files' and (select public.is_admin()));
drop policy if exists print_files_admin_insert on storage.objects;
create policy print_files_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'print-files' and (select public.is_admin()));
drop policy if exists print_files_admin_update on storage.objects;
create policy print_files_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'print-files' and (select public.is_admin()))
  with check (bucket_id = 'print-files' and (select public.is_admin()));
drop policy if exists print_files_admin_delete on storage.objects;
create policy print_files_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'print-files' and (select public.is_admin()));
