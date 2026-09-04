-- Persist protected Vet AI inference output and audit metadata.

alter table public.assessments
  add column if not exists animal_group public.animal_group,
  add column if not exists ai_analysis jsonb not null default '{}'::jsonb,
  add column if not exists ai_model text,
  add column if not exists ai_provider_request_id text,
  add column if not exists ai_usage jsonb not null default '{}'::jsonb,
  add column if not exists ai_generated_at timestamptz;

create index if not exists assessments_farm_created_idx
  on public.assessments (farm_id, created_at desc);

create index if not exists assessments_ai_generated_idx
  on public.assessments (ai_generated_at desc)
  where ai_generated_at is not null;
