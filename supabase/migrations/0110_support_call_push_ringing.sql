create table if not exists public.support_call_push_deliveries (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.support_calls(id) on delete cascade,
  device_scope text not null check (device_scope in ('admin','farm')),
  device_id uuid not null,
  recipient_user_id uuid,
  status text not null default 'sending' check (status in ('sending','sent','failed')),
  apns_id text,
  error text,
  created_at timestamptz not null default now(),
  sent_at timestamptz,
  unique(call_id, device_scope, device_id)
);

alter table public.support_call_push_deliveries enable row level security;
revoke all on public.support_call_push_deliveries from anon, authenticated;
grant select, insert, update, delete on public.support_call_push_deliveries to service_role;

create index if not exists support_call_push_deliveries_call_idx
  on public.support_call_push_deliveries(call_id, created_at desc);

create or replace function public.dispatch_support_call_push()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'ringing' then
    return new;
  end if;

  perform net.http_post(
    url := 'https://mzqwjyantyvizwbzetwf.supabase.co/functions/v1/support-call-push',
    body := jsonb_build_object('call_id', new.id),
    headers := jsonb_build_object('Content-Type', 'application/json'),
    timeout_milliseconds := 5000
  );
  return new;
exception when others then
  raise warning 'Vet AI support call push queue failed for call %: %', new.id, sqlerrm;
  return new;
end;
$$;

revoke all on function public.dispatch_support_call_push() from public, anon, authenticated;
grant execute on function public.dispatch_support_call_push() to service_role;

drop trigger if exists vet_ai_support_call_push on public.support_calls;
create trigger vet_ai_support_call_push
after insert on public.support_calls
for each row execute function public.dispatch_support_call_push();
