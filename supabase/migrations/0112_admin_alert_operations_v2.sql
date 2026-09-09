-- Vet AI alert operations for administration.

alter table public.alerts add column if not exists admin_status text not null default 'open';
alter table public.alerts drop constraint if exists alerts_admin_status_check;
alter table public.alerts add constraint alerts_admin_status_check check (admin_status in ('open','acknowledged','resolved','hidden'));
alter table public.alerts add column if not exists admin_notes text;
alter table public.alerts add column if not exists resolved_at timestamptz;
alter table public.alerts add column if not exists resolved_by uuid references auth.users(id) on delete set null;

update public.alerts set admin_status='acknowledged' where acknowledged_at is not null and admin_status='open';

drop trigger if exists audit_alerts_admin on public.alerts;
create trigger audit_alerts_admin after insert or update or delete on public.alerts for each row execute function public.admin_audit_trigger();
drop trigger if exists audit_animals_admin on public.animals;
create trigger audit_animals_admin after insert or update or delete on public.animals for each row execute function public.admin_audit_trigger();

create or replace function public.admin_set_alert_status(p_alert_id uuid,p_status text,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_admin_account('alerts') then raise exception 'Alert permission required'; end if;
  if p_status not in ('open','acknowledged','resolved','hidden') then raise exception 'Invalid alert status'; end if;
  update public.alerts
  set admin_status=p_status,
      admin_notes=case when p_notes is null then admin_notes else nullif(trim(p_notes),'') end,
      acknowledged_at=case when p_status in ('acknowledged','resolved') then coalesce(acknowledged_at,now()) when p_status='open' then null else acknowledged_at end,
      acknowledged_by=case when p_status in ('acknowledged','resolved') then coalesce(acknowledged_by,auth.uid()) when p_status='open' then null else acknowledged_by end,
      resolved_at=case when p_status='resolved' then coalesce(resolved_at,now()) when p_status in ('open','acknowledged') then null else resolved_at end,
      resolved_by=case when p_status='resolved' then coalesce(resolved_by,auth.uid()) when p_status in ('open','acknowledged') then null else resolved_by end
  where id=p_alert_id;
end; $$;
revoke all on function public.admin_set_alert_status(uuid,text,text) from public,anon;
grant execute on function public.admin_set_alert_status(uuid,text,text) to authenticated;
