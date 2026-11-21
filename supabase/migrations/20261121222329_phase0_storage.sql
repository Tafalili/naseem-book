insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('order-photos', 'order-photos', false, 5242880,  array['image/jpeg','image/png','image/webp']),
  ('receipts',     'receipts',     false, 5242880,  array['image/jpeg','image/png','image/webp','application/pdf']),
  ('templates',    'templates',    true,  31457280, array['image/jpeg','image/png','image/webp','image/svg+xml']);

-- private buckets: guest writes only inside {uid}/ ; owner of folder or admin reads
create policy guest_upload_own on storage.objects for insert to authenticated
  with check (bucket_id in ('order-photos','receipts')
              and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy guest_update_own on storage.objects for update to authenticated
  using (bucket_id in ('order-photos','receipts')
         and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id in ('order-photos','receipts')
              and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy guest_delete_own on storage.objects for delete to authenticated
  using (bucket_id in ('order-photos','receipts')
         and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy private_read_own_or_admin on storage.objects for select to authenticated
  using (bucket_id in ('order-photos','receipts')
         and ((storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin())));

create policy admin_manage_private on storage.objects for delete to authenticated
  using (bucket_id in ('order-photos','receipts') and (select public.is_admin()));

-- templates: public bucket (CDN read), admin write
create policy templates_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'templates' and (select public.is_admin()));
create policy templates_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'templates' and (select public.is_admin()))
  with check (bucket_id = 'templates' and (select public.is_admin()));
create policy templates_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'templates' and (select public.is_admin()));
