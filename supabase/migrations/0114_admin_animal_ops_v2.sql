-- Vet AI animal administration additions.

alter table public.animals add column if not exists admin_notes text;
alter table public.animals add column if not exists updated_at timestamptz not null default now();
drop trigger if exists trg_animals_touch on public.animals;
create trigger trg_animals_touch before update on public.animals for each row execute function public.touch_updated_at();
