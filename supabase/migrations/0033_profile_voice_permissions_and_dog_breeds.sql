alter table public.farms
  add column if not exists dog_breeds text[] not null default '{}';

grant select, insert, update on table public.profiles to authenticated;
grant insert, select on table public.voice_client_events to authenticated;
grant insert, select on table public.voice_client_events to service_role;
grant insert, select on table public.voice_provider_events to service_role;

drop policy if exists profiles_self_insert on public.profiles;
create policy profiles_self_insert
on public.profiles
for insert
to authenticated
with check (id = auth.uid());
