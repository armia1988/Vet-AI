-- Vet AI backend follow-up: onboarding fields, private RLS helper, and explicit client grants.

alter table public.farms
  add column if not exists barn_count integer not null default 1 check (barn_count >= 1),
  add column if not exists livestock_count integer not null default 0 check (livestock_count >= 0),
  add column if not exists poultry_count integer not null default 0 check (poultry_count >= 0),
  add column if not exists dog_count integer not null default 0 check (dog_count >= 0),
  add column if not exists breeds text,
  add column if not exists age_range text,
  add column if not exists subscription_tier text not null default 'software' check (subscription_tier in ('software','smart_monitoring')),
  add column if not exists billing_cycle text not null default 'monthly' check (billing_cycle in ('monthly','annual'));

create index if not exists farms_owner_created_idx on public.farms(owner_id, created_at desc);

alter function public.set_updated_at() set search_path = public;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.is_farm_member(target_farm uuid)
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

revoke all on function private.is_farm_member(uuid) from public, anon;
grant execute on function private.is_farm_member(uuid) to authenticated;

alter policy farms_member_select on public.farms using (private.is_farm_member(id));
alter policy farm_members_member_select on public.farm_members using (private.is_farm_member(farm_id));
alter policy barns_member_all on public.barns using (private.is_farm_member(farm_id)) with check (private.is_farm_member(farm_id));
alter policy animals_member_all on public.animals using (private.is_farm_member(farm_id)) with check (private.is_farm_member(farm_id));
alter policy flocks_member_all on public.flocks using (private.is_farm_member(farm_id)) with check (private.is_farm_member(farm_id));
alter policy assessments_member_all on public.assessments using (private.is_farm_member(farm_id)) with check (private.is_farm_member(farm_id));
alter policy sensor_devices_member_all on public.sensor_devices using (private.is_farm_member(farm_id)) with check (private.is_farm_member(farm_id));
alter policy sensor_readings_member_select on public.sensor_readings using (private.is_farm_member(farm_id));
alter policy alerts_member_all on public.alerts using (private.is_farm_member(farm_id)) with check (private.is_farm_member(farm_id));

drop function if exists public.is_farm_member(uuid);

grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.farms to authenticated;
grant select, insert, update, delete on public.farm_members to authenticated;
grant select, insert, update, delete on public.barns to authenticated;
grant select, insert, update, delete on public.animals to authenticated;
grant select, insert, update, delete on public.flocks to authenticated;
grant select, insert, update, delete on public.assessments to authenticated;
grant select, insert, update, delete on public.sensor_devices to authenticated;
grant select on public.sensor_readings to authenticated;
grant select, insert, update, delete on public.alerts to authenticated;
grant usage, select on sequence public.sensor_readings_id_seq to authenticated;
