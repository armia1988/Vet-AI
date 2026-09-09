alter table public.farms
  add column if not exists profile_photo_path text,
  add column if not exists profile_photo_updated_at timestamptz;

alter table public.support_messages
  add column if not exists message_type text not null default 'text',
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.support_messages
set message_type = case
  when attachment_path is not null and coalesce(attachment_mime,'') like 'image/%' then 'image'
  when attachment_path is not null then 'file'
  else coalesce(nullif(message_type,''),'text')
end
where message_type = 'text' and attachment_path is not null;

create table if not exists public.support_poll_votes (
  message_id uuid not null references public.support_messages(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  option_index integer not null check (option_index >= 0 and option_index < 20),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

alter table public.support_poll_votes enable row level security;

drop policy if exists support_poll_votes_access on public.support_poll_votes;
create policy support_poll_votes_access on public.support_poll_votes
for all to authenticated
using (
  exists (
    select 1
    from public.support_messages m
    join public.support_threads st on st.id = m.thread_id
    where m.id = support_poll_votes.message_id
      and (
        public.is_admin_account('support')
        or private.is_farm_member(st.farm_id)
      )
  )
)
with check (
  user_id = auth.uid()
  and exists (
    select 1
    from public.support_messages m
    join public.support_threads st on st.id = m.thread_id
    where m.id = support_poll_votes.message_id
      and (
        public.is_admin_account('support')
        or private.is_farm_member(st.farm_id)
      )
  )
);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values (
  'farm-profile',
  'farm-profile',
  false,
  5242880,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists farm_profile_read on storage.objects;
create policy farm_profile_read on storage.objects
for select to authenticated
using (
  bucket_id = 'farm-profile'
  and (
    public.is_admin_account()
    or exists (
      select 1 from public.farms f
      where f.id::text = (storage.foldername(name))[1]
        and private.is_farm_member(f.id)
    )
  )
);

drop policy if exists farm_profile_insert on storage.objects;
create policy farm_profile_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'farm-profile'
  and (
    public.is_admin_account('farms')
    or exists (
      select 1 from public.farms f
      where f.id::text = (storage.foldername(name))[1]
        and f.owner_id = auth.uid()
    )
  )
);

drop policy if exists farm_profile_update on storage.objects;
create policy farm_profile_update on storage.objects
for update to authenticated
using (
  bucket_id = 'farm-profile'
  and (
    public.is_admin_account('farms')
    or exists (
      select 1 from public.farms f
      where f.id::text = (storage.foldername(name))[1]
        and f.owner_id = auth.uid()
    )
  )
)
with check (
  bucket_id = 'farm-profile'
  and (
    public.is_admin_account('farms')
    or exists (
      select 1 from public.farms f
      where f.id::text = (storage.foldername(name))[1]
        and f.owner_id = auth.uid()
    )
  )
);

drop policy if exists farm_profile_delete on storage.objects;
create policy farm_profile_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'farm-profile'
  and (
    public.is_admin_account('farms')
    or exists (
      select 1 from public.farms f
      where f.id::text = (storage.foldername(name))[1]
        and f.owner_id = auth.uid()
    )
  )
);

create or replace function public.cast_support_poll_vote(
  p_message_id uuid,
  p_option_index integer
)
returns void
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required';
  end if;
  insert into public.support_poll_votes(message_id,user_id,option_index)
  values (p_message_id,auth.uid(),p_option_index)
  on conflict (message_id,user_id) do update
    set option_index = excluded.option_index,
        created_at = now();
end;
$$;

grant execute on function public.cast_support_poll_vote(uuid,integer) to authenticated;
