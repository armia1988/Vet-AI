-- Vet AI Admin Control Center v2
-- Customer account controls + global system switches.

alter table public.profiles add column if not exists account_status text not null default 'active';
alter table public.profiles drop constraint if exists profiles_account_status_check;
alter table public.profiles add constraint profiles_account_status_check check (account_status in ('active','suspended','closed'));
alter table public.profiles add column if not exists admin_notes text;
alter table public.profiles add column if not exists admin_tags text[] not null default '{}';
alter table public.profiles add column if not exists last_admin_review_at timestamptz;
alter table public.profiles add column if not exists last_admin_reviewed_by uuid references auth.users(id) on delete set null;

create table if not exists public.admin_system_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  description text,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);
alter table public.admin_system_settings enable row level security;

drop policy if exists admin_system_settings_admin_read on public.admin_system_settings;
create policy admin_system_settings_admin_read on public.admin_system_settings for select to authenticated using (public.is_admin_account('system'));
drop policy if exists admin_system_settings_admin_manage on public.admin_system_settings;
create policy admin_system_settings_admin_manage on public.admin_system_settings for all to authenticated using (public.is_admin_account('system')) with check (public.is_admin_account('system'));

grant select,insert,update,delete on public.admin_system_settings to authenticated;

insert into public.admin_system_settings(key,value,description) values
('maintenance_mode','false'::jsonb,'Block normal customer access while maintenance is active.'),
('customer_signup_enabled','true'::jsonb,'Allow new customer signup/onboarding.'),
('sensor_ingest_enabled','true'::jsonb,'Allow sensor hardware to submit readings.'),
('sensor_alert_push_enabled','true'::jsonb,'Allow sensor alert APNs delivery.'),
('admin_broadcast_push_enabled','true'::jsonb,'Allow admin broadcast notifications.'),
('support_push_enabled','true'::jsonb,'Allow support-message push notifications to admin devices.'),
('default_currency','"EUR"'::jsonb,'Default billing currency.'),
('default_trial_days','14'::jsonb,'Default free trial duration in days.'),
('sensor_offline_minutes','10'::jsonb,'Minutes without contact before a sensor is considered offline.'),
('support_sla_hours','24'::jsonb,'Default support response target in hours.')
on conflict (key) do nothing;

create or replace function public.touch_admin_system_settings()
returns trigger language plpgsql security invoker set search_path=public as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  return new;
end; $$;
drop trigger if exists trg_admin_system_settings_touch on public.admin_system_settings;
create trigger trg_admin_system_settings_touch before insert or update on public.admin_system_settings for each row execute function public.touch_admin_system_settings();

drop trigger if exists audit_profiles_admin on public.profiles;
create trigger audit_profiles_admin after update on public.profiles for each row execute function public.admin_audit_trigger();
drop trigger if exists audit_admin_system_settings on public.admin_system_settings;
create trigger audit_admin_system_settings after insert or update or delete on public.admin_system_settings for each row execute function public.admin_audit_trigger();

create or replace function private.is_farm_member(target_farm uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce((select p.account_status = 'active' from public.profiles p where p.id = auth.uid()), true)
    and (
      exists (select 1 from public.farms f where f.id = target_farm and f.owner_id = auth.uid())
      or exists (select 1 from public.farm_members fm where fm.farm_id = target_farm and fm.user_id = auth.uid())
    );
$$;

create or replace function public.my_account_status()
returns text language sql stable security definer set search_path=public as $$
  select coalesce((select account_status from public.profiles where id=auth.uid()), 'active');
$$;
grant execute on function public.my_account_status() to authenticated;

create or replace function public.admin_set_customer_status(p_user_id uuid, p_status text, p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin_account('customers') then raise exception 'Admin permission required'; end if;
  if p_status not in ('active','suspended','closed') then raise exception 'Invalid account status'; end if;
  update public.profiles
     set account_status=p_status,
         admin_notes=case when p_reason is null or trim(p_reason)='' then admin_notes else trim(p_reason) end,
         last_admin_review_at=now(),
         last_admin_reviewed_by=auth.uid(),
         updated_at=now()
   where id=p_user_id;
  if p_status <> 'active' then
    update public.push_devices set enabled=false, updated_at=now() where user_id=p_user_id;
  end if;
end; $$;
revoke all on function public.admin_set_customer_status(uuid,text,text) from public,anon;
grant execute on function public.admin_set_customer_status(uuid,text,text) to authenticated;
