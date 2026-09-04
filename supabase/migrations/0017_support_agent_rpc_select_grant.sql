-- Restore the SELECT privilege required by the SECURITY INVOKER support-agent RPC.
-- RLS still limits authenticated users to their own support_agents row.
grant select on table public.support_agents to authenticated;
revoke all on table public.support_agents from anon;
