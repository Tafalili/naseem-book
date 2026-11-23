-- Automatic deletion of customer photos and deposit receipts.
--
-- An order's files are due once:
--   * it was printed (printed_at, or shipped/delivered without a printing step)
--     more than app_settings.purge_after_print_hours ago, or
--   * it never went ahead (pending_deposit / cancelled) and is older than
--     app_settings.purge_max_days.
-- Orders still in production are never touched.
--
-- Files can only be removed through the Storage API, so the hourly pg_cron job
-- calls the `purge-photos` Edge Function, which asks purge_plan() what to delete,
-- removes it, then reports back with purge_done().
-- Auth reuses the Vault secret `order_events_secret`.

create extension if not exists pg_cron;

-- ---------- which orders are due ----------
create or replace function public.purge_due_orders()
returns setof uuid language sql stable security definer set search_path = ''
as $$
  select o.id
  from public.orders o, public.app_settings s
  where s.id and o.images_purged_at is null
    and (
      coalesce(o.printed_at, case when o.status in ('shipped', 'delivered') then o.updated_at end)
        < now() - make_interval(hours => s.purge_after_print_hours)
      or (o.status in ('pending_deposit', 'cancelled')
          and o.created_at < now() - make_interval(days => s.purge_max_days))
    )
$$;
revoke all on function public.purge_due_orders() from public, anon, authenticated;

-- Everything an order points at, as text, to look file names up in.
create or replace function public.order_file_refs(p_order uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select concat_ws(' ',
    (select concat_ws(' ', o.receipt_path, o.cover_config::text) from public.orders o where o.id = p_order),
    (select string_agg(b.cover_config::text, ' ') from public.order_books b where b.order_id = p_order),
    (select string_agg(concat_ws(' ', p.photo_path, p.slots::text), ' ') from public.order_pages p where p.order_id = p_order),
    (select string_agg(concat_ws(' ', i.photos::text, i.fields::text), ' ') from public.order_items i where i.order_id = p_order))
$$;
revoke all on function public.order_file_refs(uuid) from public, anon, authenticated;

-- ---------- plan: what the Edge Function should delete ----------
-- A file goes when no order that must keep its files points at it, and either a
-- due order points at it or it was never attached to any order (an upload whose
-- checkout did not finish) and is older than two days.
create or replace function public.purge_plan(p_secret text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_due uuid[];
  v_keep text;
  v_due_refs text;
  v_all_refs text;
begin
  if p_secret is distinct from (select decrypted_secret from vault.decrypted_secrets where name = 'order_events_secret') then
    raise exception 'forbidden';
  end if;

  select coalesce(array_agg(d), '{}') into v_due from public.purge_due_orders() d;

  select coalesce(string_agg(public.order_file_refs(o.id), ' '), '') into v_keep
  from public.orders o where o.images_purged_at is null and not (o.id = any (v_due));
  select coalesce(string_agg(public.order_file_refs(d), ' '), '') into v_due_refs
  from unnest(v_due) d;
  v_all_refs := v_keep || ' ' || v_due_refs;

  return jsonb_build_object(
    'orders', to_jsonb(v_due),
    'files', coalesce((
      select jsonb_agg(jsonb_build_object('bucket', f.bucket_id, 'name', f.name))
      from (
        select so.bucket_id, so.name
        from storage.objects so
        where so.bucket_id in ('order-photos', 'receipts')
          and strpos(v_keep, so.name) = 0
          and (strpos(v_due_refs, so.name) > 0
               or (strpos(v_all_refs, so.name) = 0 and so.created_at < now() - interval '2 days'))
        order by so.created_at
        limit 1000
      ) f), '[]'::jsonb));
end $$;
revoke all on function public.purge_plan(text) from public, anon, authenticated;
grant execute on function public.purge_plan(text) to service_role;

-- ---------- done: mark orders whose files are gone ----------
create or replace function public.purge_done(p_secret text, p_orders uuid[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare n integer;
begin
  if p_secret is distinct from (select decrypted_secret from vault.decrypted_secrets where name = 'order_events_secret') then
    raise exception 'forbidden';
  end if;
  update public.orders set images_purged_at = now()
  where id = any (p_orders) and images_purged_at is null
    and id in (select public.purge_due_orders());
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.purge_done(text, uuid[]) from public, anon, authenticated;
grant execute on function public.purge_done(text, uuid[]) to service_role;

-- ---------- hourly job ----------
create or replace function public.run_photo_purge()
returns void language plpgsql security definer set search_path = ''
as $$
declare secret text;
begin
  select decrypted_secret into secret from vault.decrypted_secrets where name = 'order_events_secret';
  if secret is null then return; end if;
  perform net.http_post(
    url := 'https://edarzlqkxgobdffcfnpx.supabase.co/functions/v1/purge-photos',
    body := '{}'::jsonb,
    headers := jsonb_build_object('content-type', 'application/json', 'x-order-events-secret', secret),
    timeout_milliseconds := 60000);
end $$;
revoke all on function public.run_photo_purge() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'photo-purge';
select cron.schedule('photo-purge', '17 * * * *', 'select public.run_photo_purge()');
