-- Expand Vet AI admin audit coverage.

drop trigger if exists audit_subscription_plans_admin on public.subscription_plans;
create trigger audit_subscription_plans_admin after insert or update or delete on public.subscription_plans for each row execute function public.admin_audit_trigger();
drop trigger if exists audit_admin_notifications_admin on public.admin_notifications;
create trigger audit_admin_notifications_admin after insert or update or delete on public.admin_notifications for each row execute function public.admin_audit_trigger();
drop trigger if exists audit_support_threads_admin on public.support_threads;
create trigger audit_support_threads_admin after insert or update or delete on public.support_threads for each row execute function public.admin_audit_trigger();
drop trigger if exists audit_sensor_rules_admin on public.sensor_alert_rules;
create trigger audit_sensor_rules_admin after insert or update or delete on public.sensor_alert_rules for each row execute function public.admin_audit_trigger();
drop trigger if exists audit_push_devices_admin on public.push_devices;
create trigger audit_push_devices_admin after insert or update or delete on public.push_devices for each row execute function public.admin_audit_trigger();
drop trigger if exists audit_admin_push_devices_admin on public.admin_push_devices;
create trigger audit_admin_push_devices_admin after insert or update or delete on public.admin_push_devices for each row execute function public.admin_audit_trigger();
