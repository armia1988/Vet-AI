create table if not exists public.support_webrtc_signals (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.support_calls(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  signal_type text not null check (signal_type in ('offer','answer','candidate')),
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists support_webrtc_signals_call_created_idx
  on public.support_webrtc_signals(call_id, created_at);

alter table public.support_webrtc_signals enable row level security;

drop policy if exists support_webrtc_signals_access on public.support_webrtc_signals;
create policy support_webrtc_signals_access
on public.support_webrtc_signals
for all
to authenticated
using (
  exists (
    select 1
    from public.support_calls c
    join public.support_threads st on st.id = c.thread_id
    where c.id = support_webrtc_signals.call_id
      and (
        public.is_admin_account('support'::text)
        or private.is_farm_member(st.farm_id)
      )
  )
)
with check (
  sender_id = auth.uid()
  and exists (
    select 1
    from public.support_calls c
    join public.support_threads st on st.id = c.thread_id
    where c.id = support_webrtc_signals.call_id
      and (
        public.is_admin_account('support'::text)
        or private.is_farm_member(st.farm_id)
      )
  )
);

grant select, insert on public.support_webrtc_signals to authenticated;

create table if not exists public.support_webrtc_turn_config (
  id uuid primary key default gen_random_uuid(),
  label text not null default 'primary',
  urls text[] not null,
  username text not null,
  credential text not null,
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.support_webrtc_turn_config enable row level security;
revoke all on public.support_webrtc_turn_config from anon, authenticated;

create or replace function public.get_support_webrtc_ice(p_call_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  allowed boolean := false;
  servers jsonb := jsonb_build_array(
    jsonb_build_object(
      'urls', jsonb_build_array(
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302'
      )
    )
  );
  cfg record;
  configured boolean := false;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select exists (
    select 1
    from public.support_calls c
    join public.support_threads st on st.id = c.thread_id
    where c.id = p_call_id
      and (
        public.is_admin_account('support'::text)
        or private.is_farm_member(st.farm_id)
      )
  ) into allowed;

  if not allowed then
    raise exception 'support call access denied';
  end if;

  for cfg in
    select urls, username, credential
    from public.support_webrtc_turn_config
    where active = true
      and (expires_at is null or expires_at > now() + interval '5 minutes')
    order by created_at desc
  loop
    configured := true;
    servers := servers || jsonb_build_array(
      jsonb_build_object(
        'urls', to_jsonb(cfg.urls),
        'username', cfg.username,
        'credential', cfg.credential
      )
    );
  end loop;

  return jsonb_build_object(
    'iceServers', servers,
    'turnConfigured', configured
  );
end;
$$;

revoke all on function public.get_support_webrtc_ice(uuid) from public;
grant execute on function public.get_support_webrtc_ice(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'support_calls'
  ) then
    alter publication supabase_realtime add table public.support_calls;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'support_webrtc_signals'
  ) then
    alter publication supabase_realtime add table public.support_webrtc_signals;
  end if;
end $$;
