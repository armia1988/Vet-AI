-- Vet AI Admin A-Z expansion.
alter table public.sensor_devices add column if not exists display_name text;
alter table public.sensor_devices add column if not exists section_name text;
alter table public.sensor_devices add column if not exists admin_notes text;
alter table public.sensor_devices add column if not exists admin_disabled_reason text;

create table if not exists public.admin_account_invites (
  id uuid primary key default gen_random_uuid(), email text not null, full_name text, phone text,
  preferred_language text not null default 'en', kind text not null default 'customer'
    check (kind in ('customer','admin','support','operations','billing','worker')),
  admin_role text, permissions jsonb not null default '{}'::jsonb,
  farm_id uuid references public.farms(id) on delete set null, member_role public.member_role,
  create_farm boolean not null default false, company_name text, farm_name text, country text, region text,
  token_hash text not null unique, expires_at timestamptz not null default (now()+interval '7 days'),
  accepted_at timestamptz, accepted_by uuid references auth.users(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete cascade, created_at timestamptz not null default now()
);
create unique index if not exists admin_account_invites_active_email_idx
  on public.admin_account_invites(lower(email)) where accepted_at is null;
alter table public.admin_account_invites enable row level security;
drop policy if exists admin_account_invites_admin_read on public.admin_account_invites;
create policy admin_account_invites_admin_read on public.admin_account_invites for select to authenticated
  using (public.is_admin_account('manage_admins'));
drop policy if exists admin_account_invites_admin_manage on public.admin_account_invites;
create policy admin_account_invites_admin_manage on public.admin_account_invites for all to authenticated
  using (public.is_admin_account('manage_admins')) with check (public.is_admin_account('manage_admins'));
grant select,insert,update,delete on public.admin_account_invites to authenticated;

create or replace function public.admin_create_account_invite(
  p_email text,p_full_name text default null,p_phone text default null,p_preferred_language text default 'en',
  p_kind text default 'customer',p_admin_role text default null,p_permissions jsonb default '{}'::jsonb,
  p_farm_id uuid default null,p_member_role text default null,p_create_farm boolean default false,
  p_company_name text default null,p_farm_name text default null,p_country text default null,p_region text default null)
returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare v_email text:=lower(trim(coalesce(p_email,''))); v_token text; v_id uuid; v_member public.member_role;
begin
  if not public.is_admin_account('manage_admins') then raise exception 'Admin permission required'; end if;
  if v_email='' or position('@' in v_email)<2 then raise exception 'Valid email required'; end if;
  if p_kind not in ('customer','admin','support','operations','billing','worker') then raise exception 'Invalid account kind'; end if;
  if p_kind='admin' and coalesce(p_admin_role,'admin') not in ('super_admin','admin','support','billing','operations') then raise exception 'Invalid admin role'; end if;
  if nullif(trim(coalesce(p_member_role,'')),'') is not null then v_member:=trim(p_member_role)::public.member_role; end if;
  if p_create_farm and trim(coalesce(p_farm_name,''))='' then raise exception 'Farm name required'; end if;
  delete from public.admin_account_invites where lower(email)=v_email and accepted_at is null;
  v_token:=encode(gen_random_bytes(32),'hex');
  insert into public.admin_account_invites(email,full_name,phone,preferred_language,kind,admin_role,permissions,farm_id,member_role,create_farm,company_name,farm_name,country,region,token_hash,created_by)
  values(v_email,nullif(trim(coalesce(p_full_name,'')),''),nullif(trim(coalesce(p_phone,'')),''),coalesce(nullif(trim(p_preferred_language),''),'en'),p_kind,p_admin_role,coalesce(p_permissions,'{}'::jsonb),p_farm_id,v_member,coalesce(p_create_farm,false),nullif(trim(coalesce(p_company_name,'')),''),nullif(trim(coalesce(p_farm_name,'')),''),nullif(trim(coalesce(p_country,'')),''),nullif(trim(coalesce(p_region,'')),''),encode(digest(v_token,'sha256'),'hex'),auth.uid()) returning id into v_id;
  return jsonb_build_object('id',v_id,'token',v_token,'email',v_email,'kind',p_kind,'expires_at',now()+interval '7 days');
end; $$;
revoke all on function public.admin_create_account_invite(text,text,text,text,text,text,jsonb,uuid,text,boolean,text,text,text,text) from public,anon;
grant execute on function public.admin_create_account_invite(text,text,text,text,text,text,jsonb,uuid,text,boolean,text,text,text,text) to authenticated;

create or replace function public.account_invite_preview(p_token text) returns jsonb
language plpgsql stable security definer set search_path=public,extensions as $$
declare v public.admin_account_invites%rowtype;
begin
  select * into v from public.admin_account_invites
   where token_hash=encode(digest(coalesce(p_token,''),'sha256'),'hex') and accepted_at is null and expires_at>now() limit 1;
  if v.id is null then return jsonb_build_object('valid',false); end if;
  return jsonb_build_object('valid',true,'email',v.email,'full_name',v.full_name,'kind',v.kind,'expires_at',v.expires_at);
end; $$;
revoke all on function public.account_invite_preview(text) from public;
grant execute on function public.account_invite_preview(text) to anon,authenticated;

create or replace function public.claim_account_invite(p_token text) returns jsonb
language plpgsql security definer set search_path=public,extensions as $$
declare v public.admin_account_invites%rowtype; v_email text:=lower(coalesce(auth.jwt()->>'email','')); v_role text; v_farm uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v from public.admin_account_invites
   where token_hash=encode(digest(coalesce(p_token,''),'sha256'),'hex') and accepted_at is null and expires_at>now()
   for update skip locked limit 1;
  if v.id is null then raise exception 'Invite is invalid or expired'; end if;
  if v_email='' or lower(v.email)<>v_email then raise exception 'Invite email does not match signed-in account'; end if;
  update public.profiles set full_name=coalesce(v.full_name,full_name),phone=coalesce(v.phone,phone),preferred_language=coalesce(v.preferred_language,preferred_language),account_status='active',updated_at=now() where id=auth.uid();
  if v.kind in ('admin','support','operations','billing') then
    v_role:=case when v.kind='admin' then coalesce(v.admin_role,'admin') else v.kind end;
    insert into public.admin_accounts(user_id,role,active,permissions) values(auth.uid(),v_role,true,coalesce(v.permissions,'{}'::jsonb))
    on conflict(user_id) do update set role=excluded.role,active=true,permissions=excluded.permissions,updated_at=now();
  end if;
  if v.create_farm then
    insert into public.farms(owner_id,company_name,farm_name,country,region)
    values(auth.uid(),v.company_name,coalesce(v.farm_name,'Vet AI farm'),v.country,v.region) returning id into v_farm;
  elsif v.farm_id is not null then
    v_farm:=v.farm_id;
    insert into public.farm_members(farm_id,user_id,role) values(v.farm_id,auth.uid(),coalesce(v.member_role,'worker'::public.member_role))
    on conflict(farm_id,user_id) do update set role=excluded.role;
  end if;
  update public.admin_account_invites set accepted_at=now(),accepted_by=auth.uid() where id=v.id;
  return jsonb_build_object('ok',true,'kind',v.kind,'is_admin',v.kind in ('admin','support','operations','billing'),'farm_id',v_farm);
end; $$;
revoke all on function public.claim_account_invite(text) from public,anon;
grant execute on function public.claim_account_invite(text) to authenticated;

create or replace function public.admin_create_sensor_device(
  p_farm_id uuid,p_device_uid text,p_display_name text,p_device_type text,p_section_name text default null,
  p_firmware_version text default null,p_active boolean default true,p_admin_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.is_admin_account('sensors') then raise exception 'Sensor admin permission required'; end if;
  if not exists(select 1 from public.farms where id=p_farm_id) then raise exception 'Farm not found'; end if;
  if trim(coalesce(p_device_uid,''))='' then raise exception 'Device UID required'; end if;
  if trim(coalesce(p_device_type,''))='' then raise exception 'Device type required'; end if;
  insert into public.sensor_devices(farm_id,device_uid,display_name,device_type,section_name,firmware_version,active,admin_notes)
  values(p_farm_id,trim(p_device_uid),nullif(trim(coalesce(p_display_name,'')),''),trim(p_device_type),nullif(trim(coalesce(p_section_name,'')),''),nullif(trim(coalesce(p_firmware_version,'')),''),coalesce(p_active,true),nullif(trim(coalesce(p_admin_notes,'')),'')) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.admin_create_sensor_device(uuid,text,text,text,text,text,boolean,text) from public,anon;
grant execute on function public.admin_create_sensor_device(uuid,text,text,text,text,text,boolean,text) to authenticated;

create table if not exists public.support_calls(
 id uuid primary key default gen_random_uuid(),thread_id uuid not null references public.support_threads(id) on delete cascade,
 initiated_by uuid not null references auth.users(id) on delete cascade,caller_role text not null check(caller_role in ('user','support')),
 call_type text not null check(call_type in ('voice','video')),status text not null default 'ringing' check(status in ('ringing','accepted','declined','ended','missed')),
 room_key text not null unique default encode(gen_random_bytes(18),'hex'),created_at timestamptz not null default now(),answered_at timestamptz,ended_at timestamptz);
alter table public.support_calls enable row level security;
drop policy if exists support_calls_thread_access on public.support_calls;
create policy support_calls_thread_access on public.support_calls for all to authenticated
using(public.is_admin_account('support') or exists(select 1 from public.support_threads st where st.id=thread_id and private.is_farm_member(st.farm_id)))
with check(public.is_admin_account('support') or exists(select 1 from public.support_threads st where st.id=thread_id and private.is_farm_member(st.farm_id)));
grant select,insert,update on public.support_calls to authenticated;
