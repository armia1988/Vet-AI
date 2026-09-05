alter table public.profiles
  add column if not exists scan_privacy_acknowledged_at timestamptz;

grant select, update on table public.profiles to authenticated;
