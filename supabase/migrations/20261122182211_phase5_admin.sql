-- Phase 5: admin panel support.
--  * owner notifications by email (Resend) + Web Push to admin browsers (Telegram dropped:
--    blocked in Iraq without a VPN)
--  * admin_set_status(): one audited way to move an order, with a note for the customer
--  * admin_list(): owner sees staff with their emails

alter table public.app_settings
  add column if not exists notify_email text check (notify_email is null or notify_email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$');
update public.app_settings set notify_email = coalesce(notify_email, 'opdcmustafa@gmail.com') where id;

create table if not exists public.admin_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null check (char_length(endpoint) <= 1000),
  keys jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, endpoint)
);
alter table public.admin_push_subscriptions enable row level security;
create policy admin_push_own_read on public.admin_push_subscriptions for select to authenticated
  using (user_id = (select auth.uid()) and (select public.is_admin()));
create policy admin_push_own_insert on public.admin_push_subscriptions for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.is_admin()));
create policy admin_push_own_update on public.admin_push_subscriptions for update to authenticated
  using (user_id = (select auth.uid()) and (select public.is_admin()))
  with check (user_id = (select auth.uid()) and (select public.is_admin()));
create policy admin_push_own_delete on public.admin_push_subscriptions for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---------- status changes ----------
create or replace function public.admin_set_status(p_order_id uuid, p_status public.order_status, p_note text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  cur public.order_status;
  v_note text := nullif(left(btrim(coalesce(p_note, '')), 500), '');
begin
  if not (select public.is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  select status into cur from public.orders where id = p_order_id for update;
  if not found then raise exception 'order_not_found'; end if;
  if cur = p_status then return; end if;
  -- sending a receipt back needs a reason the customer can read
  if cur = 'deposit_review' and p_status = 'pending_deposit' and v_note is null then
    raise exception 'note_required';
  end if;
  perform set_config('app.status_note', coalesce(v_note, ''), true);
  update public.orders
     set status = p_status,
         printed_at = case when p_status = 'printing' and printed_at is null then now() else printed_at end
   where id = p_order_id;
  perform set_config('app.status_note', '', true);
end $$;
revoke all on function public.admin_set_status(uuid, public.order_status, text) from public, anon;
grant execute on function public.admin_set_status(uuid, public.order_status, text) to authenticated;

-- staff may not edit prices, totals or customer data directly; status goes through the RPC above
alter policy orders_admin_update on public.orders
  using ((select public.is_owner())) with check ((select public.is_owner()));
alter policy orders_admin_update on public.orders rename to orders_owner_update;

-- ---------- team ----------
create or replace function public.admin_list()
returns table (user_id uuid, email text, role public.admin_role, display_name text, created_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  select a.user_id, u.email::text, a.role, a.display_name, a.created_at
    from public.admins a join auth.users u on u.id = a.user_id
   where (select public.is_owner())
   order by a.created_at
$$;
revoke all on function public.admin_list() from public, anon;
grant execute on function public.admin_list() to authenticated;

-- ---------- edge function config: drop telegram, add owner email ----------
create or replace function public.order_events_config(p_secret text)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select case when p_secret = (select decrypted_secret from vault.decrypted_secrets where name = 'order_events_secret')
    then jsonb_build_object(
      'vapid_public', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_public'),
      'vapid_private', (select decrypted_secret from vault.decrypted_secrets where name = 'vapid_private'),
      'notify_email', (select s.notify_email from public.app_settings s where s.id))
  end
$$;
revoke all on function public.order_events_config(text) from public, anon, authenticated;
grant execute on function public.order_events_config(text) to service_role;
