create or replace function public.sync_farm_subscription_summary()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan_code text;
begin
  if tg_op = 'DELETE' then
    update public.farms
    set subscription_status = 'cancelled', subscription_updated_at = now()
    where id = old.farm_id;
    return old;
  end if;

  select code into v_plan_code from public.subscription_plans where id = new.plan_id;
  update public.farms
  set subscription_tier = coalesce(v_plan_code, subscription_tier),
      billing_cycle = new.billing_cycle,
      subscription_status = new.status,
      subscription_updated_at = now()
  where id = new.farm_id;
  return new;
end;
$$;

drop trigger if exists farm_subscription_summary_sync on public.farm_subscriptions;
create trigger farm_subscription_summary_sync
after insert or update or delete on public.farm_subscriptions
for each row execute function public.sync_farm_subscription_summary();

create or replace function public.sync_paid_payment_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'paid' and new.subscription_id is not null then
    update public.farm_subscriptions
    set status = 'active', updated_at = now()
    where id = new.subscription_id and status <> 'cancelled';
  end if;
  return new;
end;
$$;

drop trigger if exists paid_payment_subscription_sync on public.payments;
create trigger paid_payment_subscription_sync
after insert or update of status on public.payments
for each row execute function public.sync_paid_payment_subscription();
