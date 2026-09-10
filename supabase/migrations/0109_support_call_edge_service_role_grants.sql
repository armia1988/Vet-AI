-- Vet AI support-call Edge Functions run with the Supabase service role.
-- These explicit grants are required because several core tables intentionally
-- use narrowed grants instead of broad defaults. RLS remains enabled for
-- normal authenticated users; service_role is used only by trusted server code.

grant select, update on table public.support_calls to service_role;
grant select on table public.support_threads to service_role;
grant select on table public.farm_members to service_role;
grant select on table public.admin_accounts to service_role;
