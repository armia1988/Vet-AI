create table if not exists public.animal_ai_followups (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  animal_id uuid not null references public.animals(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  offset_hours integer not null check (offset_hours in (12,24,48)),
  due_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','completed','skipped')),
  outcome text check (outcome is null or outcome in ('better','same','worse','uncertain')),
  symptom_notes text,
  temperature_c numeric,
  media_path text,
  ai_comparison jsonb not null default '{}'::jsonb,
  ai_model text,
  ai_generated_at timestamptz,
  reminder_sent_at timestamptz,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (assessment_id, offset_hours)
);

create index if not exists animal_ai_followups_farm_due_idx
  on public.animal_ai_followups (farm_id, status, due_at);
create index if not exists animal_ai_followups_animal_due_idx
  on public.animal_ai_followups (animal_id, due_at desc);

alter table public.animal_ai_followups enable row level security;

drop policy if exists animal_ai_followups_member_all on public.animal_ai_followups;
create policy animal_ai_followups_member_all
on public.animal_ai_followups
for all to authenticated
using (public.vet_is_farm_member(farm_id))
with check (public.vet_is_farm_member(farm_id));

drop trigger if exists animal_ai_followups_set_updated_at on public.animal_ai_followups;
create trigger animal_ai_followups_set_updated_at
before update on public.animal_ai_followups
for each row execute function public.set_updated_at();

create or replace function public.schedule_ai_followups_from_assessment()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  base_time timestamptz;
begin
  if new.animal_id is null or new.ai_generated_at is null then
    return new;
  end if;

  base_time := new.ai_generated_at;

  insert into public.animal_ai_followups (
    farm_id, animal_id, assessment_id, offset_hours, due_at, created_by
  ) values
    (new.farm_id, new.animal_id, new.id, 12, base_time + interval '12 hours', new.created_by),
    (new.farm_id, new.animal_id, new.id, 24, base_time + interval '24 hours', new.created_by),
    (new.farm_id, new.animal_id, new.id, 48, base_time + interval '48 hours', new.created_by)
  on conflict (assessment_id, offset_hours) do nothing;

  return new;
end;
$$;

drop trigger if exists vet_ai_schedule_followups on public.assessments;
create trigger vet_ai_schedule_followups
after insert or update of ai_generated_at on public.assessments
for each row execute function public.schedule_ai_followups_from_assessment();

insert into public.animal_ai_followups (
  farm_id, animal_id, assessment_id, offset_hours, due_at, created_by
)
select a.farm_id, a.animal_id, a.id, x.offset_hours,
       a.ai_generated_at + make_interval(hours => x.offset_hours), a.created_by
from public.assessments a
cross join (values (12),(24),(48)) as x(offset_hours)
where a.animal_id is not null
  and a.ai_generated_at is not null
  and a.ai_generated_at >= now() - interval '48 hours'
on conflict (assessment_id, offset_hours) do nothing;

create or replace function public.process_ai_followup_reminders()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  created_alert_id uuid;
  processed integer := 0;
begin
  for r in
    select
      f.id,
      f.farm_id,
      f.animal_id,
      f.offset_hours,
      f.due_at,
      coalesce(nullif(trim(a.name), ''), nullif(trim(a.external_id), ''), nullif(trim(a.species), ''), 'Animal') as animal_label
    from public.animal_ai_followups f
    join public.animals a on a.id = f.animal_id
    where f.status = 'pending'
      and f.reminder_sent_at is null
      and f.due_at <= now() + interval '30 minutes'
      and f.due_at >= now() - interval '24 hours'
    for update of f skip locked
  loop
    insert into public.alerts (
      farm_id, animal_id, risk, title, details, source, metric, threshold_text
    ) values (
      r.farm_id,
      r.animal_id,
      'yellow',
      'Vet AI follow-up due',
      r.animal_label || ' · ' || r.offset_hours || '-hour follow-up is due. Add a new photo, symptoms and temperature so Vet AI can compare progress.',
      'ai_followup_reminder',
      'ai_followup_due',
      r.due_at::text
    ) returning id into created_alert_id;

    update public.animal_ai_followups
    set reminder_sent_at = now()
    where id = r.id;

    processed := processed + 1;
  end loop;

  return jsonb_build_object('followups_reminded', processed, 'processed_at', now());
end;
$$;

revoke all on function public.process_ai_followup_reminders() from public, anon, authenticated;
grant execute on function public.process_ai_followup_reminders() to service_role, postgres;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'vet-ai-ai-followups'
  order by jobid desc
  limit 1;
  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
end;
$$;

select cron.schedule(
  'vet-ai-ai-followups',
  '*/15 * * * *',
  $cmd$select public.process_ai_followup_reminders();$cmd$
);
