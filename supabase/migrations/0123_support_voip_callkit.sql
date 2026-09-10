-- Vet AI V66 — dedicated iOS PushKit/CallKit registration for real incoming support calls.

create table if not exists public.voip_push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  farm_id uuid null references public.farms(id) on delete cascade,
  scope text not null default 'farm' check (scope in ('farm','admin')),
  platform text not null default 'ios' check (platform = 'ios'),
  device_token text not null unique,
  environment text not null default 'production' check (environment in ('production','sandbox')),
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists voip_push_devices_user_idx
  on public.voip_push_devices(user_id) where enabled;
create index if not exists voip_push_devices_farm_idx
  on public.voip_push_devices(farm_id) where enabled;

alter table public.voip_push_devices enable row level security;

revoke all on public.voip_push_devices from anon, authenticated;
grant select on public.voip_push_devices to authenticated;
grant all on public.voip_push_devices to service_role;

drop policy if exists voip_push_devices_own_select on public.voip_push_devices;
create policy voip_push_devices_own_select
  on public.voip_push_devices
  for select
  to authenticated
  using (user_id = auth.uid());

create or replace function public.register_voip_push_device(
  p_device_token text,
  p_environment text default 'production',
  p_farm_id uuid default null,
  p_scope text default 'farm'
) returns uuid
language plpgsql
security definer
set search_path = public, private, auth
as $$
declare
  v_user uuid := auth.uid();
  v_token text := lower(trim(coalesce(p_device_token, '')));
  v_environment text := lower(trim(coalesce(p_environment, 'production')));
  v_scope text := lower(trim(coalesce(p_scope, 'farm')));
  v_id uuid;
begin
  if v_user is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if v_token !~ '^[0-9a-f]{64,}$' then
    raise exception 'invalid_voip_device_token' using errcode = '22023';
  end if;
  if v_environment not in ('production','sandbox') then
    raise exception 'invalid_environment' using errcode = '22023';
  end if;
  if v_scope not in ('farm','admin') then
    raise exception 'invalid_scope' using errcode = '22023';
  end if;

  if v_scope = 'admin' then
    if not public.is_admin_account('support') then
      raise exception 'admin_support_permission_required' using errcode = '42501';
    end if;
    p_farm_id := null;
  else
    if p_farm_id is null or not private.is_farm_member(p_farm_id) then
      raise exception 'farm_membership_required' using errcode = '42501';
    end if;
  end if;

  insert into public.voip_push_devices(
    user_id, farm_id, scope, device_token, environment, enabled, updated_at
  ) values (
    v_user, p_farm_id, v_scope, v_token, v_environment, true, now()
  )
  on conflict (device_token) do update set
    user_id = excluded.user_id,
    farm_id = excluded.farm_id,
    scope = excluded.scope,
    environment = excluded.environment,
    enabled = true,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.disable_voip_push_device(p_device_token text)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  update public.voip_push_devices
     set enabled = false, updated_at = now()
   where user_id = auth.uid()
     and device_token = lower(trim(coalesce(p_device_token, '')));
end;
$$;

grant execute on function public.register_voip_push_device(text,text,uuid,text) to authenticated;
grant execute on function public.disable_voip_push_device(text) to authenticated;

alter table public.support_call_push_deliveries
  add column if not exists transport text not null default 'alert';
alter table public.support_call_push_deliveries
  add column if not exists event_type text not null default 'ringing';

alter table public.support_call_push_deliveries
  drop constraint if exists support_call_push_deliveries_call_id_device_scope_device_id_key;

drop index if exists public.support_call_push_deliveries_call_scope_device_event_uidx;
create unique index support_call_push_deliveries_call_scope_device_event_uidx
  on public.support_call_push_deliveries(call_id, device_scope, device_id, event_type);

create or replace function public.dispatch_support_call_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_url text;
  v_headers jsonb;
  v_body jsonb;
begin
  if tg_op = 'INSERT' and new.status <> 'ringing' then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;
  if new.status not in ('ringing','ended','declined') then
    return new;
  end if;

  v_url := 'https://mzqwjyantyvizwbzetwf.supabase.co/functions/v1/support-call-push';
  v_headers := jsonb_build_object('Content-Type','application/json');
  v_body := jsonb_build_object('call_id', new.id, 'event', new.status);

  perform net.http_post(
    url := v_url,
    headers := v_headers,
    body := v_body,
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  raise warning 'dispatch_support_call_push failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists vet_ai_support_call_push on public.support_calls;
create trigger vet_ai_support_call_push
  after insert or update of status on public.support_calls
  for each row execute function public.dispatch_support_call_push();
