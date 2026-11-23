begin;
create table public.alert_followups (
  id bigint generated always as identity primary key,
  alert_id uuid not null references public.alerts(id) on delete cascade,
  at timestamptz not null default now(),
  author uuid not null default auth.uid(),
  assignee text not null check (length(trim(assignee)) between 1 and 160),
  note text not null check (length(trim(note)) between 1 and 4000),
  closed boolean not null
);
create index on public.alert_followups(alert_id,id desc);
alter table public.alert_followups enable row level security;
revoke all on public.alert_followups from public, anon, authenticated;
grant select, insert(alert_id,assignee,note,closed) on public.alert_followups to authenticated;
create policy visible_alert_history on public.alert_followups for select to authenticated
using (exists (select from public.alerts a where a.id=alert_id));
create policy farm_owner_updates on public.alert_followups for insert to authenticated
with check (author=auth.uid() and exists (select from public.alerts a join public.farms f on f.id=a.farm_id where a.id=alert_id and f.owner_id=auth.uid()));
create view public.alert_team_summary with (security_invoker=true) as
select a.id,a.farm_id,f.farm_name,to_jsonb(a)->>'barn_id' as barn,
 a.title,a.created_at,a.risk,coalesce(e.closed,false) as closed,e.assignee,e.note
from public.alerts a join public.farms f on f.id=a.farm_id
left join lateral (select closed,assignee,note from public.alert_followups
 where alert_id=a.id order by id desc limit 1) e on true;
grant select on public.alert_team_summary to authenticated;
create view public.alert_team_comparison with (security_invoker=true) as
select farm_id,farm_name,barn,count(*) as total,count(*) filter(where not closed) as pending,
 count(*) filter(where created_at>=now()-interval '7 days') as this_week,
 count(*) filter(where created_at>=now()-interval '14 days' and created_at<now()-interval '7 days') as last_week
from public.alert_team_summary group by farm_id,farm_name,barn;
grant select on public.alert_team_comparison to authenticated;
commit;
