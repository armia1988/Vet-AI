-- Vet AI Admin Control Center v1
-- Applied to production Supabase project mzqwjyantyvizwbzetwf.

create table if not exists public.admin_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'support' check (role in ('super_admin','admin','support','billing','operations')),
  active boolean not null default true,
  permissions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.admin_accounts enable row level security;

create or replace function public.is_admin_account(required_permission text default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admin_accounts a
    where a.user_id = auth.uid() and a.active = true
      and (required_permission is null or a.role in ('super_admin','admin')
        or coalesce((a.permissions ->> required_permission)::boolean, false) = true)
  );
$$;
grant execute on function public.is_admin_account(text) to authenticated;

create or replace function public.my_admin_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.admin_accounts where user_id = auth.uid() and active = true limit 1;
$$;
grant execute on function public.my_admin_role() to authenticated;

create policy admin_accounts_self_select on public.admin_accounts for select to authenticated
using (user_id = auth.uid() or public.is_admin_account('manage_admins'));
create policy admin_accounts_super_manage on public.admin_accounts for all to authenticated
using (public.is_admin_account('manage_admins')) with check (public.is_admin_account('manage_admins'));

alter table public.sensor_devices add column if not exists display_name text;
alter table public.sensor_devices add column if not exists section_name text;
alter table public.sensor_devices add column if not exists admin_notes text;
alter table public.sensor_devices add column if not exists admin_disabled_reason text;
alter table public.sensor_devices add column if not exists updated_at timestamptz not null default now();

alter table public.support_threads add column if not exists assigned_to uuid references auth.users(id) on delete set null;
alter table public.support_threads add column if not exists priority text not null default 'normal' check (priority in ('low','normal','high','urgent'));
alter table public.support_threads add column if not exists unread_by_admin integer not null default 0;
alter table public.support_threads add column if not exists unread_by_customer integer not null default 0;
alter table public.support_threads add column if not exists last_message_at timestamptz;

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(), code text unique not null, name text not null,
  description text, currency text not null default 'EUR', monthly_price numeric(12,2) not null default 0,
  yearly_price numeric(12,2) not null default 0, max_farms integer, max_sensors integer,
  features jsonb not null default '{}'::jsonb, active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.farm_subscriptions (
  id uuid primary key default gen_random_uuid(), farm_id uuid not null references public.farms(id) on delete cascade,
  plan_id uuid references public.subscription_plans(id) on delete set null,
  status text not null default 'trial' check (status in ('trial','active','past_due','paused','cancelled','expired')),
  billing_cycle text not null default 'monthly' check (billing_cycle in ('monthly','yearly','manual')),
  currency text not null default 'EUR', amount numeric(12,2) not null default 0,
  started_at timestamptz not null default now(), current_period_start timestamptz, current_period_end timestamptz,
  trial_ends_at timestamptz, cancelled_at timestamptz, external_customer_id text, external_subscription_id text,
  notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists farm_subscriptions_one_live_idx on public.farm_subscriptions(farm_id) where status in ('trial','active','past_due','paused');

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(), farm_id uuid not null references public.farms(id) on delete cascade,
  subscription_id uuid references public.farm_subscriptions(id) on delete set null,
  amount numeric(12,2) not null, currency text not null default 'EUR',
  status text not null default 'pending' check (status in ('pending','paid','failed','refunded','cancelled')),
  provider text not null default 'manual', provider_payment_id text, invoice_number text, description text,
  paid_at timestamptz, due_at timestamptz, metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.admin_notifications (
  id uuid primary key default gen_random_uuid(), created_by uuid not null references auth.users(id) on delete restrict,
  target_scope text not null check (target_scope in ('all','farm','user')),
  farm_id uuid references public.farms(id) on delete cascade, user_id uuid references auth.users(id) on delete cascade,
  title text not null, body text not null, severity text not null default 'info' check (severity in ('info','orange','red')),
  status text not null default 'draft' check (status in ('draft','sending','sent','partial','failed')),
  sent_count integer not null default 0, failed_count integer not null default 0,
  created_at timestamptz not null default now(), sent_at timestamptz
);

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key, actor_user_id uuid references auth.users(id) on delete set null,
  action text not null, table_name text not null, record_id text, old_data jsonb, new_data jsonb,
  created_at timestamptz not null default now()
);

alter table public.subscription_plans enable row level security;
alter table public.farm_subscriptions enable row level security;
alter table public.payments enable row level security;
alter table public.admin_notifications enable row level security;
alter table public.admin_audit_log enable row level security;

create policy subscription_plans_authenticated_read on public.subscription_plans for select to authenticated using (active = true or public.is_admin_account('billing'));
create policy subscription_plans_admin_manage on public.subscription_plans for all to authenticated using (public.is_admin_account('billing')) with check (public.is_admin_account('billing'));
create policy farm_subscriptions_member_read on public.farm_subscriptions for select to authenticated using (private.is_farm_member(farm_id) or public.is_admin_account('billing'));
create policy farm_subscriptions_admin_manage on public.farm_subscriptions for all to authenticated using (public.is_admin_account('billing')) with check (public.is_admin_account('billing'));
create policy payments_member_read on public.payments for select to authenticated using (private.is_farm_member(farm_id) or public.is_admin_account('billing'));
create policy payments_admin_manage on public.payments for all to authenticated using (public.is_admin_account('billing')) with check (public.is_admin_account('billing'));
create policy admin_notifications_admin_all on public.admin_notifications for all to authenticated using (public.is_admin_account('notifications')) with check (public.is_admin_account('notifications'));
create policy admin_audit_admin_read on public.admin_audit_log for select to authenticated using (public.is_admin_account('audit'));
create policy profiles_admin_select on public.profiles for select to authenticated using (public.is_admin_account('customers'));
create policy profiles_admin_update on public.profiles for update to authenticated using (public.is_admin_account('customers')) with check (public.is_admin_account('customers'));
create policy farms_admin_all on public.farms for all to authenticated using (public.is_admin_account('farms')) with check (public.is_admin_account('farms'));
create policy animals_admin_all on public.animals for all to authenticated using (public.is_admin_account('animals')) with check (public.is_admin_account('animals'));
create policy alerts_admin_all on public.alerts for all to authenticated using (public.is_admin_account('alerts')) with check (public.is_admin_account('alerts'));
create policy sensor_devices_admin_all on public.sensor_devices for all to authenticated using (public.is_admin_account('sensors')) with check (public.is_admin_account('sensors'));
create policy sensor_readings_admin_select on public.sensor_readings for select to authenticated using (public.is_admin_account('sensors'));
create policy sensor_alert_rules_admin_all on public.sensor_alert_rules for all to authenticated using (public.is_admin_account('sensors')) with check (public.is_admin_account('sensors'));
create policy support_threads_admin_all on public.support_threads for all to authenticated using (public.is_admin_account('support')) with check (public.is_admin_account('support'));
create policy support_messages_admin_all on public.support_messages for all to authenticated using (public.is_admin_account('support')) with check (public.is_admin_account('support'));
create policy push_devices_admin_all on public.push_devices for all to authenticated using (public.is_admin_account('notifications')) with check (public.is_admin_account('notifications'));
create policy push_deliveries_admin_select on public.push_deliveries for select to authenticated using (public.is_admin_account('notifications'));
create policy whatsapp_prefs_admin_all on public.whatsapp_alert_preferences for all to authenticated using (public.is_admin_account('notifications')) with check (public.is_admin_account('notifications'));
create policy whatsapp_deliveries_admin_select on public.whatsapp_deliveries for select to authenticated using (public.is_admin_account('notifications'));

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end $$;
create trigger trg_admin_accounts_touch before update on public.admin_accounts for each row execute function public.touch_updated_at();
create trigger trg_sensor_devices_touch before update on public.sensor_devices for each row execute function public.touch_updated_at();
create trigger trg_subscription_plans_touch before update on public.subscription_plans for each row execute function public.touch_updated_at();
create trigger trg_farm_subscriptions_touch before update on public.farm_subscriptions for each row execute function public.touch_updated_at();
create trigger trg_payments_touch before update on public.payments for each row execute function public.touch_updated_at();

create or replace function public.admin_audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin_account(null) then
    insert into public.admin_audit_log(actor_user_id,action,table_name,record_id,old_data,new_data)
    values(auth.uid(),tg_op,tg_table_name,coalesce((case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'id',''),
      case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
      case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  end if;
  return case when tg_op='DELETE' then old else new end;
end; $$;
create trigger audit_farms_admin after insert or update or delete on public.farms for each row execute function public.admin_audit_trigger();
create trigger audit_sensor_devices_admin after insert or update or delete on public.sensor_devices for each row execute function public.admin_audit_trigger();
create trigger audit_farm_subscriptions_admin after insert or update or delete on public.farm_subscriptions for each row execute function public.admin_audit_trigger();
create trigger audit_payments_admin after insert or update or delete on public.payments for each row execute function public.admin_audit_trigger();
create trigger audit_admin_accounts_admin after insert or update or delete on public.admin_accounts for each row execute function public.admin_audit_trigger();

create or replace function public.support_thread_message_counters()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.support_threads set updated_at=now(), last_message_at=new.created_at,
    unread_by_admin=unread_by_admin + case when new.sender_role='user' then 1 else 0 end,
    unread_by_customer=unread_by_customer + case when new.sender_role='support' then 1 else 0 end
  where id=new.thread_id;
  return new;
end; $$;
create trigger support_message_counters after insert on public.support_messages for each row execute function public.support_thread_message_counters();

insert into public.subscription_plans(code,name,description,currency,monthly_price,yearly_price,max_farms,max_sensors,features)
values
('starter','Starter','Core Vet AI monitoring','EUR',19,190,1,10,'{"support":true,"alerts":true}'),
('professional','Professional','Advanced farm monitoring','EUR',49,490,3,100,'{"support":true,"alerts":true,"advanced_sensors":true,"reports":true}'),
('enterprise','Enterprise','Large company and multi-farm operations','EUR',149,1490,null,null,'{"support":true,"alerts":true,"advanced_sensors":true,"reports":true,"priority_support":true,"multi_farm":true}')
on conflict (code) do nothing;
