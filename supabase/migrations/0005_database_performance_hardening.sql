-- Performance hardening after the first functional backend rollout.

create index if not exists alerts_acknowledged_by_idx on public.alerts (acknowledged_by);
create index if not exists alerts_animal_id_idx on public.alerts (animal_id);
create index if not exists alerts_assessment_id_idx on public.alerts (assessment_id);
create index if not exists alerts_farm_id_idx on public.alerts (farm_id);
create index if not exists alerts_flock_id_idx on public.alerts (flock_id);
create index if not exists animals_barn_id_idx on public.animals (barn_id);
create index if not exists assessments_animal_id_idx on public.assessments (animal_id);
create index if not exists assessments_created_by_idx on public.assessments (created_by);
create index if not exists assessments_flock_id_idx on public.assessments (flock_id);
create index if not exists barns_farm_id_idx on public.barns (farm_id);
create index if not exists farm_members_user_id_idx on public.farm_members (user_id);
create index if not exists flocks_barn_id_idx on public.flocks (barn_id);
create index if not exists flocks_farm_id_idx on public.flocks (farm_id);
create index if not exists sensor_devices_animal_id_idx on public.sensor_devices (animal_id);
create index if not exists sensor_devices_barn_id_idx on public.sensor_devices (barn_id);
create index if not exists sensor_devices_farm_id_idx on public.sensor_devices (farm_id);
create index if not exists sensor_readings_device_id_idx on public.sensor_readings (device_id);

drop policy if exists profiles_self_select on public.profiles;
create policy profiles_self_select on public.profiles
for select to authenticated using (id = (select auth.uid()));

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

drop policy if exists farms_owner_insert on public.farms;
create policy farms_owner_insert on public.farms
for insert to authenticated with check (owner_id = (select auth.uid()));

drop policy if exists farms_owner_update on public.farms;
create policy farms_owner_update on public.farms
for update to authenticated
using (owner_id = (select auth.uid()))
with check (owner_id = (select auth.uid()));

drop policy if exists farms_owner_delete on public.farms;
create policy farms_owner_delete on public.farms
for delete to authenticated using (owner_id = (select auth.uid()));

drop policy if exists farm_members_member_select on public.farm_members;
drop policy if exists farm_members_owner_manage on public.farm_members;

create policy farm_members_member_select on public.farm_members
for select to authenticated using (private.is_farm_member(farm_id));

create policy farm_members_owner_insert on public.farm_members
for insert to authenticated
with check (exists (
  select 1 from public.farms f
  where f.id = farm_id and f.owner_id = (select auth.uid())
));

create policy farm_members_owner_update on public.farm_members
for update to authenticated
using (exists (
  select 1 from public.farms f
  where f.id = farm_id and f.owner_id = (select auth.uid())
))
with check (exists (
  select 1 from public.farms f
  where f.id = farm_id and f.owner_id = (select auth.uid())
));

create policy farm_members_owner_delete on public.farm_members
for delete to authenticated
using (exists (
  select 1 from public.farms f
  where f.id = farm_id and f.owner_id = (select auth.uid())
));
