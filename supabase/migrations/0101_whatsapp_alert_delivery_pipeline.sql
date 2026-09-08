-- Vet AI WhatsApp alert delivery foundation.
-- Safe by default: preferences are created disabled and no WhatsApp message is sent
-- until the farm owner explicitly enables the channel and provider credentials exist.

create table if not exists public.whatsapp_alert_preferences (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  recipient_user_id uuid not null references public.profiles(id) on delete cascade,
  enabled boolean not null default false,
  minimum_risk text not null default 'orange' check (minimum_risk in ('orange','red')),
  phone_e164 text,
  language text,
  recipient_role text not null default 'owner',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (farm_id, recipient_user_id)
);

create index if not exists whatsapp_alert_preferences_farm_enabled_idx
  on public.whatsapp_alert_preferences(farm_id, enabled);

alter table public.whatsapp_alert_preferences enable row level security;

drop policy if exists whatsapp_alert_preferences_owner_select on public.whatsapp_alert_preferences;
create policy whatsapp_alert_preferences_owner_select
on public.whatsapp_alert_preferences
for select
to authenticated
using (exists (
  select 1 from public.farms f
  where f.id = farm_id and f.owner_id = auth.uid()
));

drop policy if exists whatsapp_alert_preferences_owner_insert on public.whatsapp_alert_preferences;
create policy whatsapp_alert_preferences_owner_insert
on public.whatsapp_alert_preferences
for insert
to authenticated
with check (
  recipient_user_id = auth.uid()
  and exists (
    select 1 from public.farms f
    where f.id = farm_id and f.owner_id = auth.uid()
  )
);

drop policy if exists whatsapp_alert_preferences_owner_update on public.whatsapp_alert_preferences;
create policy whatsapp_alert_preferences_owner_update
on public.whatsapp_alert_preferences
for update
to authenticated
using (exists (
  select 1 from public.farms f
  where f.id = farm_id and f.owner_id = auth.uid()
))
with check (
  recipient_user_id = auth.uid()
  and exists (
    select 1 from public.farms f
    where f.id = farm_id and f.owner_id = auth.uid()
  )
);

drop policy if exists whatsapp_alert_preferences_owner_delete on public.whatsapp_alert_preferences;
create policy whatsapp_alert_preferences_owner_delete
on public.whatsapp_alert_preferences
for delete
to authenticated
using (exists (
  select 1 from public.farms f
  where f.id = farm_id and f.owner_id = auth.uid()
));

insert into public.whatsapp_alert_preferences(
  farm_id, recipient_user_id, enabled, minimum_risk, language, recipient_role
)
select f.id, f.owner_id, false, 'orange', coalesce(nullif(trim(p.preferred_language),''),'en'), 'owner'
from public.farms f
left join public.profiles p on p.id = f.owner_id
on conflict (farm_id, recipient_user_id) do nothing;

create table if not exists public.whatsapp_deliveries (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references public.alerts(id) on delete cascade,
  farm_id uuid not null references public.farms(id) on delete cascade,
  recipient_user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('sending','sent','failed','skipped')),
  provider text not null default 'meta_cloud_api',
  provider_message_id text,
  template_name text,
  error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(alert_id, recipient_user_id)
);

create index if not exists whatsapp_deliveries_farm_created_idx
  on public.whatsapp_deliveries(farm_id, created_at desc);
create index if not exists whatsapp_deliveries_status_created_idx
  on public.whatsapp_deliveries(status, created_at desc);

alter table public.whatsapp_deliveries enable row level security;

drop policy if exists whatsapp_deliveries_farm_read on public.whatsapp_deliveries;
create policy whatsapp_deliveries_farm_read
on public.whatsapp_deliveries
for select
to authenticated
using (private.is_farm_member(farm_id));

create or replace function public.dispatch_alert_to_whatsapp()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.risk::text not in ('orange','red') then
    return new;
  end if;

  perform net.http_post(
    url := 'https://mzqwjyantyvizwbzetwf.supabase.co/functions/v1/vet-ai-whatsapp-alert',
    body := jsonb_build_object('alert_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json'),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  raise warning 'Vet AI WhatsApp dispatch queue failed for alert %: %', new.id, sqlerrm;
  return new;
end;
$$;

revoke all on function public.dispatch_alert_to_whatsapp() from public;
revoke all on function public.dispatch_alert_to_whatsapp() from anon;
revoke all on function public.dispatch_alert_to_whatsapp() from authenticated;

drop trigger if exists vet_ai_alert_whatsapp on public.alerts;
create trigger vet_ai_alert_whatsapp
after insert on public.alerts
for each row
execute function public.dispatch_alert_to_whatsapp();

-- Remove an obsolete duplicate sensor trigger that attempted to insert source='sensor_rule',
-- which violates the current alerts_source_check. The private trigger remains the canonical
-- real-sensor alert creator and uses source='sensor'.
drop trigger if exists trg_evaluate_sensor_alert_rules on public.sensor_readings;
