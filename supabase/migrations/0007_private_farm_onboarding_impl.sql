drop function if exists public.create_farm_onboarding(jsonb);

create or replace function private.create_farm_onboarding_impl(p jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user uuid := auth.uid();
  v_farm uuid;
  v_barn_count integer := greatest(coalesce((p->>'barn_count')::integer, 1), 1);
  v_area numeric := greatest(coalesce((p->>'total_indoor_area_m2')::numeric, 0), 0);
  v_livestock integer := greatest(coalesce((p->>'livestock_count')::integer, 0), 0);
  v_poultry integer := greatest(coalesce((p->>'poultry_count')::integer, 0), 0);
  v_dogs integer := greatest(coalesce((p->>'dog_count')::integer, 0), 0);
  v_group public.animal_group;
begin
  if v_user is null then raise exception 'Authentication required' using errcode = '28000'; end if;
  if nullif(trim(coalesce(p->>'farm_name','')), '') is null then
    raise exception 'Farm name is required' using errcode = '22023';
  end if;

  v_group := case
    when v_livestock > 0 then 'livestock'::public.animal_group
    when v_poultry > 0 then 'poultry'::public.animal_group
    when v_dogs > 0 then 'dogs'::public.animal_group
    else 'livestock'::public.animal_group
  end;

  insert into public.farms (
    owner_id, company_name, farm_name, country, region,
    worker_count, veterinarian_count, total_indoor_area_m2,
    production_purpose, ventilation_system, vaccination_notes, disease_history,
    barn_count, livestock_count, poultry_count, dog_count,
    breeds, age_range, subscription_tier, billing_cycle
  ) values (
    v_user,
    nullif(trim(coalesce(p->>'company_name','')), ''),
    trim(p->>'farm_name'),
    nullif(trim(coalesce(p->>'country','')), ''),
    nullif(trim(coalesce(p->>'region','')), ''),
    greatest(coalesce((p->>'worker_count')::integer, 0), 0),
    greatest(coalesce((p->>'veterinarian_count')::integer, 0), 0),
    v_area,
    nullif(trim(coalesce(p->>'production_purpose','')), ''),
    nullif(trim(coalesce(p->>'ventilation_system','')), ''),
    nullif(trim(coalesce(p->>'vaccination_notes','')), ''),
    nullif(trim(coalesce(p->>'disease_history','')), ''),
    v_barn_count, v_livestock, v_poultry, v_dogs,
    nullif(trim(coalesce(p->>'breeds','')), ''),
    nullif(trim(coalesce(p->>'age_range','')), ''),
    case when p->>'subscription_tier' = 'smart_monitoring' then 'smart_monitoring' else 'software' end,
    case when p->>'billing_cycle' = 'annual' then 'annual' else 'monthly' end
  ) returning id into v_farm;

  insert into public.farm_members(farm_id, user_id, role)
  values (v_farm, v_user, 'owner')
  on conflict (farm_id, user_id) do nothing;

  insert into public.barns(farm_id, name, animal_group, indoor_area_m2)
  select v_farm, 'Barn ' || g::text, v_group,
         case when v_area > 0 then v_area / v_barn_count else 0 end
  from generate_series(1, v_barn_count) g;

  if v_livestock > 0 then
    insert into public.flocks(farm_id, animal_group, name, head_count, breed_or_strain, production_cycle)
    values (v_farm, 'livestock', 'Primary livestock group', v_livestock,
      nullif(trim(coalesce(p->>'breeds','')), ''), nullif(trim(coalesce(p->>'age_range','')), ''));
  end if;
  if v_poultry > 0 then
    insert into public.flocks(farm_id, animal_group, name, head_count, breed_or_strain, production_cycle)
    values (v_farm, 'poultry', 'Primary poultry flock', v_poultry,
      nullif(trim(coalesce(p->>'breeds','')), ''), nullif(trim(coalesce(p->>'age_range','')), ''));
  end if;
  if v_dogs > 0 then
    insert into public.flocks(farm_id, animal_group, name, head_count, breed_or_strain, production_cycle)
    values (v_farm, 'dogs', 'Dogs', v_dogs,
      nullif(trim(coalesce(p->>'breeds','')), ''), nullif(trim(coalesce(p->>'age_range','')), ''));
  end if;

  return v_farm;
end;
$$;

revoke all on function private.create_farm_onboarding_impl(jsonb) from public, anon;
grant execute on function private.create_farm_onboarding_impl(jsonb) to authenticated;

create or replace function public.create_farm_onboarding(p jsonb)
returns uuid
language sql
security invoker
set search_path = public, private, pg_temp
as $$ select private.create_farm_onboarding_impl(p); $$;

revoke all on function public.create_farm_onboarding(jsonb) from public, anon;
grant execute on function public.create_farm_onboarding(jsonb) to authenticated;
