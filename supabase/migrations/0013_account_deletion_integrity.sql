-- Vet AI V19: make account deletion compatible with historical clinical records.
--
-- If a user who created a case or sensor rule is deleted, keep the record but
-- detach the deleted identity. Farm-owned records still follow their existing
-- farm cascade rules when the farm itself is deleted.

alter table public.assessments
  alter column created_by drop not null;

alter table public.assessments
  drop constraint if exists assessments_created_by_fkey;

alter table public.assessments
  add constraint assessments_created_by_fkey
  foreign key (created_by)
  references auth.users(id)
  on delete set null;

alter table public.sensor_alert_rules
  drop constraint if exists sensor_alert_rules_created_by_fkey;

alter table public.sensor_alert_rules
  add constraint sensor_alert_rules_created_by_fkey
  foreign key (created_by)
  references auth.users(id)
  on delete set null;
