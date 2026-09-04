alter table public.support_messages
  add column if not exists attachment_path text,
  add column if not exists attachment_name text,
  add column if not exists attachment_mime text,
  add column if not exists attachment_size_bytes bigint,
  add column if not exists annotated_from_message_id uuid references public.support_messages(id) on delete set null;

alter table public.support_messages alter column message drop not null;
alter table public.support_messages drop constraint if exists support_messages_message_check;
alter table public.support_messages drop constraint if exists support_message_payload_check;
alter table public.support_messages add constraint support_message_payload_check check (
  (message is not null and char_length(trim(message)) between 1 and 4000)
  or attachment_path is not null
);
alter table public.support_messages add constraint support_message_text_length_check check (
  message is null or char_length(message) <= 4000
);
alter table public.support_messages add constraint support_attachment_size_check check (
  attachment_size_bytes is null or (attachment_size_bytes >= 0 and attachment_size_bytes <= 26214400)
);

create index if not exists support_messages_annotated_from_idx on public.support_messages(annotated_from_message_id) where annotated_from_message_id is not null;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'support-attachments',
  'support-attachments',
  false,
  26214400,
  array[
    'image/jpeg','image/png','image/webp','image/heic','image/heif',
    'application/pdf','text/plain','text/csv',
    'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists support_attachments_member_select on storage.objects;
create policy support_attachments_member_select on storage.objects
for select to authenticated
using (
  bucket_id = 'support-attachments'
  and exists (
    select 1 from public.support_threads t
    where t.id::text = (storage.foldername(name))[1]
      and private.is_farm_member(t.farm_id)
  )
);

drop policy if exists support_attachments_member_insert on storage.objects;
create policy support_attachments_member_insert on storage.objects
for insert to authenticated
with check (
  bucket_id = 'support-attachments'
  and exists (
    select 1 from public.support_threads t
    where t.id::text = (storage.foldername(name))[1]
      and private.is_farm_member(t.farm_id)
  )
);

drop policy if exists support_attachments_owner_delete on storage.objects;
create policy support_attachments_owner_delete on storage.objects
for delete to authenticated
using (
  bucket_id = 'support-attachments'
  and owner_id = (select auth.uid()::text)
);
