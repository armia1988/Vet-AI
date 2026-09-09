-- Vet AI Admin Billing Center v2

create sequence if not exists public.vet_ai_invoice_seq start with 1001;
alter table public.payments add column if not exists refunded_at timestamptz;
alter table public.payments add column if not exists refund_amount numeric(12,2);

create or replace function public.assign_vet_ai_invoice_number()
returns trigger language plpgsql security invoker set search_path=public as $$
begin
  if new.invoice_number is null or trim(new.invoice_number) = '' then
    new.invoice_number := 'VAI-' || to_char(now(),'YYYY') || '-' || lpad(nextval('public.vet_ai_invoice_seq')::text,6,'0');
  end if;
  return new;
end; $$;

drop trigger if exists trg_payment_invoice_number on public.payments;
create trigger trg_payment_invoice_number before insert on public.payments for each row execute function public.assign_vet_ai_invoice_number();

update public.payments
set invoice_number = 'VAI-' || to_char(coalesce(created_at,now()),'YYYY') || '-' || lpad(nextval('public.vet_ai_invoice_seq')::text,6,'0')
where invoice_number is null or trim(invoice_number)='';

create or replace function public.admin_billing_summary()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare out jsonb;
begin
  if not public.is_admin_account('billing') then raise exception 'Admin billing permission required'; end if;
  select jsonb_build_object(
    'plans', (select count(*) from public.subscription_plans),
    'active_subscriptions', (select count(*) from public.farm_subscriptions where status='active'),
    'trial_subscriptions', (select count(*) from public.farm_subscriptions where status='trial'),
    'past_due_subscriptions', (select count(*) from public.farm_subscriptions where status='past_due'),
    'paid_total', coalesce((select sum(amount) from public.payments where status='paid'),0),
    'pending_total', coalesce((select sum(amount) from public.payments where status='pending'),0),
    'refunded_total', coalesce((select sum(coalesce(refund_amount,amount)) from public.payments where status='refunded'),0),
    'failed_count', (select count(*) from public.payments where status='failed')
  ) into out;
  return out;
end; $$;
grant execute on function public.admin_billing_summary() to authenticated;
