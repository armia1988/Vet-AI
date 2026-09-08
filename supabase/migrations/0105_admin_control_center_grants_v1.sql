-- Vet AI Admin Control Center grants.
-- RLS remains the authorization boundary; these grants only allow authorized
-- authenticated admin sessions to reach the policies created in 0103.

grant select, insert, update, delete on public.admin_accounts to authenticated;
grant select, insert, update, delete on public.subscription_plans to authenticated;
grant select, insert, update, delete on public.farm_subscriptions to authenticated;
grant select, insert, update, delete on public.payments to authenticated;
grant select, insert, update, delete on public.admin_notifications to authenticated;
grant select on public.admin_audit_log to authenticated;
grant select, update on public.push_devices to authenticated;
grant select on public.push_deliveries to authenticated;
grant update on public.support_threads to authenticated;

-- Existing support console uses the support_agents authorization path. Keep
-- super admins/admins authorized there as well so the new control center and
-- the established realtime support console share the same staff access.
insert into public.support_agents(user_id, role, active)
select user_id, 'admin', true
from public.admin_accounts
where role in ('super_admin','admin') and active = true
on conflict (user_id) do update set role = excluded.role, active = true;
