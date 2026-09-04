create table if not exists public.disease_reference_media (
  id uuid primary key default gen_random_uuid(),
  disease_id uuid not null references public.disease_catalog(id) on delete cascade,
  animal_group public.animal_group not null,
  species text not null,
  media_type text not null default 'image' check (media_type in ('image','video')),
  source_url text not null,
  source_org text not null,
  license_name text not null,
  license_url text,
  diagnosis_confirmation text not null check (diagnosis_confirmation in ('laboratory_confirmed','veterinarian_confirmed','official_reference')),
  visible_sign_labels text[] not null default '{}',
  body_region text,
  disease_stage text check (disease_stage is null or disease_stage in ('preclinical','early','clinical','severe','recovery')),
  feature_summary text,
  reference_storage_path text,
  checksum_sha256 text,
  review_status text not null default 'pending' check (review_status in ('pending','reviewed','rejected')),
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(disease_id, source_url)
);

create index if not exists disease_reference_media_disease_idx on public.disease_reference_media(disease_id, review_status);
create index if not exists disease_reference_media_group_idx on public.disease_reference_media(animal_group, review_status);
create index if not exists disease_reference_media_signs_gin on public.disease_reference_media using gin(visible_sign_labels);

alter table public.disease_reference_media enable row level security;
grant select on public.disease_reference_media to authenticated;

drop policy if exists disease_reference_media_reviewed_read on public.disease_reference_media;
create policy disease_reference_media_reviewed_read on public.disease_reference_media
for select to authenticated using (review_status = 'reviewed');

comment on table public.disease_reference_media is 'Veterinary reference media metadata. Production AI may use only reviewed entries with provenance, diagnosis confirmation and licensing metadata.';
