create or replace function public.vet_is_farm_member(target_farm uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.farms f
    where f.id = target_farm and f.owner_id = auth.uid()
  ) or exists (
    select 1 from public.farm_members fm
    where fm.farm_id = target_farm and fm.user_id = auth.uid()
  );
$$;

grant execute on function public.vet_is_farm_member(uuid) to authenticated;

create table if not exists public.animal_health_events (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  animal_id uuid not null references public.animals(id) on delete cascade,
  event_type text not null check (event_type in ('note','weight','temperature','diagnosis','lab','treatment','procedure','other')),
  title text not null,
  details text,
  value_numeric numeric,
  unit text,
  occurred_at timestamptz not null default now(),
  source text not null default 'manual',
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists animal_health_events_animal_time_idx
  on public.animal_health_events (animal_id, occurred_at desc);
create index if not exists animal_health_events_farm_time_idx
  on public.animal_health_events (farm_id, occurred_at desc);

create table if not exists public.animal_vaccinations (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  animal_id uuid not null references public.animals(id) on delete cascade,
  vaccine_name text not null,
  dose text,
  batch_number text,
  due_at timestamptz not null,
  administered_at timestamptz,
  status text not null default 'planned' check (status in ('planned','due','administered','missed','cancelled')),
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists animal_vaccinations_farm_due_idx
  on public.animal_vaccinations (farm_id, due_at);
create index if not exists animal_vaccinations_animal_due_idx
  on public.animal_vaccinations (animal_id, due_at desc);

create table if not exists public.animal_medications (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  animal_id uuid not null references public.animals(id) on delete cascade,
  medication_name text not null,
  dose text,
  route text,
  frequency text,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  next_dose_at timestamptz,
  status text not null default 'active' check (status in ('planned','active','paused','completed','cancelled')),
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists animal_medications_farm_next_idx
  on public.animal_medications (farm_id, next_dose_at);
create index if not exists animal_medications_animal_time_idx
  on public.animal_medications (animal_id, starts_at desc);

drop trigger if exists animal_vaccinations_set_updated_at on public.animal_vaccinations;
create trigger animal_vaccinations_set_updated_at
before update on public.animal_vaccinations
for each row execute function public.set_updated_at();

drop trigger if exists animal_medications_set_updated_at on public.animal_medications;
create trigger animal_medications_set_updated_at
before update on public.animal_medications
for each row execute function public.set_updated_at();

alter table public.animal_health_events enable row level security;
alter table public.animal_vaccinations enable row level security;
alter table public.animal_medications enable row level security;

drop policy if exists animal_health_events_member_all on public.animal_health_events;
create policy animal_health_events_member_all on public.animal_health_events
for all to authenticated
using (public.vet_is_farm_member(farm_id))
with check (public.vet_is_farm_member(farm_id));

drop policy if exists animal_vaccinations_member_all on public.animal_vaccinations;
create policy animal_vaccinations_member_all on public.animal_vaccinations
for all to authenticated
using (public.vet_is_farm_member(farm_id))
with check (public.vet_is_farm_member(farm_id));

drop policy if exists animal_medications_member_all on public.animal_medications;
create policy animal_medications_member_all on public.animal_medications
for all to authenticated
using (public.vet_is_farm_member(farm_id))
with check (public.vet_is_farm_member(farm_id));

create or replace function public.farm_health_dashboard(p_farm_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.vet_is_farm_member(p_farm_id) then
    raise exception 'Not authorized for farm';
  end if;

  select jsonb_build_object(
    'active_animals', (select count(*) from public.animals a where a.farm_id = p_farm_id and a.active),
    'critical_alerts', (select count(*) from public.alerts al where al.farm_id = p_farm_id and al.risk::text in ('red','orange') and coalesce(al.admin_status,'open') not in ('resolved','closed')),
    'overdue_vaccinations', (select count(*) from public.animal_vaccinations v where v.farm_id = p_farm_id and v.status not in ('administered','cancelled') and v.due_at < now()),
    'due_vaccinations', (select count(*) from public.animal_vaccinations v where v.farm_id = p_farm_id and v.status not in ('administered','cancelled') and v.due_at >= now() and v.due_at <= now() + interval '7 days'),
    'active_medications', (select count(*) from public.animal_medications m where m.farm_id = p_farm_id and m.status in ('active','planned','paused')),
    'medication_doses_due', (select count(*) from public.animal_medications m where m.farm_id = p_farm_id and m.status = 'active' and m.next_dose_at is not null and m.next_dose_at <= now() + interval '24 hours'),
    'sensor_devices', (select count(*) from public.sensor_devices s where s.farm_id = p_farm_id and s.active),
    'sensor_offline', (select count(*) from public.sensor_devices s where s.farm_id = p_farm_id and s.active and (s.last_seen_at is null or s.last_seen_at < now() - interval '20 minutes')),
    'camera_configured', (select coalesce(sum(g.cameras_configured),0) from public.camera_gateway_status g where g.farm_id = p_farm_id),
    'camera_online', (select coalesce(sum(case when g.last_heartbeat_at >= now() - interval '2 minutes' then g.cameras_online else 0 end),0) from public.camera_gateway_status g where g.farm_id = p_farm_id),
    'camera_gateways_stale', (select count(*) from public.camera_gateway_status g where g.farm_id = p_farm_id and (g.last_heartbeat_at is null or g.last_heartbeat_at < now() - interval '2 minutes')),
    'urgent_followups', (select count(*) from public.assessments a where a.farm_id = p_farm_id and coalesce(a.urgent_vet_review,false) and a.status::text not in ('vet_reviewed','lab_confirmed')),
    'recent_ai_cases', (select count(*) from public.assessments a where a.farm_id = p_farm_id and a.ai_generated_at >= now() - interval '24 hours')
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.farm_health_dashboard(uuid) to authenticated;
