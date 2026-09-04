-- Vet AI V19 security hardening.
-- The client only needs to know whether the current authenticated user is an
-- active support agent. RLS on support_agents already limits authenticated
-- users to their own row, so this public RPC does not need SECURITY DEFINER.

create or replace function public.is_support_agent()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from public.support_agents a
    where a.user_id = (select auth.uid())
      and a.active = true
  );
$$;

revoke all on function public.is_support_agent() from public, anon;
grant execute on function public.is_support_agent() to authenticated;
