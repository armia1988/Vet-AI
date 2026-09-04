-- Support foreign-key indexes for Vet AI V5.
create index if not exists support_messages_sender_id_idx on public.support_messages(sender_id);
create index if not exists support_threads_created_by_idx on public.support_threads(created_by);
