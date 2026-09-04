-- Vet AI V5 product/account shell. Applied to production on 2026-09-04.

alter table public.profiles
  add column if not exists job_title text;

alter table public.farms
  add column if not exists subscription_status text not null default 'selected',
  add column if not exists subscription_updated_at timestamptz not null default now();

create table if not exists public.support_threads (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  subject text not null default 'Vet AI support',
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.support_threads(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  sender_role text not null default 'user' check (sender_role in ('user','support','system')),
  message text not null check (char_length(trim(message)) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists support_threads_farm_idx on public.support_threads(farm_id, created_at desc);
create index if not exists support_messages_thread_idx on public.support_messages(thread_id, created_at);

alter table public.support_threads enable row level security;
alter table public.support_messages enable row level security;

grant select, insert on public.support_threads to authenticated;
grant select, insert on public.support_messages to authenticated;

create policy support_threads_member_select on public.support_threads
for select to authenticated using (private.is_farm_member(farm_id));

create policy support_threads_member_insert on public.support_threads
for insert to authenticated
with check (created_by = (select auth.uid()) and private.is_farm_member(farm_id));

create policy support_messages_member_select on public.support_messages
for select to authenticated
using (
  exists (
    select 1 from public.support_threads t
    where t.id = support_messages.thread_id
      and private.is_farm_member(t.farm_id)
  )
);

create policy support_messages_user_insert on public.support_messages
for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and sender_role = 'user'
  and exists (
    select 1 from public.support_threads t
    where t.id = support_messages.thread_id
      and private.is_farm_member(t.farm_id)
  )
);

create or replace function private.support_auto_ack()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.sender_role = 'user' and not exists (
    select 1 from public.support_messages m
    where m.thread_id = new.thread_id and m.sender_role = 'system'
  ) then
    insert into public.support_messages(thread_id, sender_id, sender_role, message)
    values (
      new.thread_id,
      null,
      'system',
      'Your message has been received by Vet AI Support. A human support reply requires the support console to be online.'
    );
  end if;
  return new;
end;
$$;

revoke all on function private.support_auto_ack() from public, anon, authenticated;

drop trigger if exists support_messages_auto_ack on public.support_messages;
create trigger support_messages_auto_ack
after insert on public.support_messages
for each row execute function private.support_auto_ack();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='support_messages'
  ) then
    alter publication supabase_realtime add table public.support_messages;
  end if;
end $$;
