-- Vet AI support chat: allow metadata-only rich messages and persist true read receipts.

alter table public.support_messages
  add column if not exists read_at timestamptz;

alter table public.support_messages
  drop constraint if exists support_message_payload_check;

alter table public.support_messages
  add constraint support_message_payload_check check (
    (
      message is not null
      and char_length(trim(message)) between 1 and 4000
    )
    or attachment_path is not null
    or (
      message_type in ('location','poll','event','system')
      and metadata is not null
      and metadata <> '{}'::jsonb
    )
  );

create index if not exists support_messages_thread_read_idx
  on public.support_messages(thread_id, read_at, created_at);

create or replace function public.mark_support_thread_read(p_thread_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public','private','pg_temp'
as $$
declare
  v_farm_id uuid;
  v_is_support boolean := false;
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;

  select farm_id into v_farm_id
  from public.support_threads
  where id = p_thread_id;

  if v_farm_id is null then
    raise exception 'support thread not found';
  end if;

  v_is_support := public.is_support_agent()
    or public.is_admin_account('support'::text);

  if v_is_support then
    update public.support_messages
       set read_at = coalesce(read_at, now())
     where thread_id = p_thread_id
       and sender_role = 'user'
       and read_at is null;

    update public.support_threads
       set unread_by_admin = 0
     where id = p_thread_id;
    return;
  end if;

  if private.is_farm_member(v_farm_id) then
    update public.support_messages
       set read_at = coalesce(read_at, now())
     where thread_id = p_thread_id
       and sender_role = 'support'
       and read_at is null;

    update public.support_threads
       set unread_by_customer = 0
     where id = p_thread_id;
    return;
  end if;

  raise exception 'support thread access denied';
end;
$$;

revoke all on function public.mark_support_thread_read(uuid) from public;
grant execute on function public.mark_support_thread_read(uuid) to authenticated;
