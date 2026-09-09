create or replace function public.admin_create_account_invite(p_email text, p_full_name text default null::text, p_phone text default null::text, p_preferred_language text default 'en'::text, p_kind text default 'customer'::text, p_admin_role text default null::text, p_permissions jsonb default '{}'::jsonb, p_farm_id uuid default null::uuid, p_member_role text default null::text, p_create_farm boolean default false, p_company_name text default null::text, p_farm_name text default null::text, p_country text default null::text, p_region text default null::text)
returns jsonb
language plpgsql
security definer
set search_path to 'public','extensions'
as $function$
declare
  v_email text:=lower(trim(coalesce(p_email,'')));
  v_token text;
  v_id uuid;
  v_member public.member_role;
begin
  if not public.is_admin_account('manage_admins') then raise exception 'Admin permission required'; end if;
  if v_email='' or position('@' in v_email)<2 then raise exception 'Valid email required'; end if;
  if p_kind not in ('customer','admin','support','operations','billing','worker') then raise exception 'Invalid account kind'; end if;
  if p_kind='admin' and coalesce(p_admin_role,'admin') not in ('super_admin','manager','assistant_manager','admin','support','billing','operations') then raise exception 'Invalid admin role'; end if;
  if nullif(trim(coalesce(p_member_role,'')),'') is not null then v_member:=trim(p_member_role)::public.member_role; end if;
  if p_create_farm and trim(coalesce(p_farm_name,''))='' then raise exception 'Farm name required'; end if;
  delete from public.admin_account_invites where lower(email)=v_email and accepted_at is null;
  v_token:=encode(gen_random_bytes(32),'hex');
  insert into public.admin_account_invites(email,full_name,phone,preferred_language,kind,admin_role,permissions,farm_id,member_role,create_farm,company_name,farm_name,country,region,token_hash,created_by)
  values(v_email,nullif(trim(coalesce(p_full_name,'')),''),nullif(trim(coalesce(p_phone,'')),''),coalesce(nullif(trim(p_preferred_language),''),'en'),p_kind,p_admin_role,coalesce(p_permissions,'{}'::jsonb),p_farm_id,v_member,coalesce(p_create_farm,false),nullif(trim(coalesce(p_company_name,'')),''),nullif(trim(coalesce(p_farm_name,'')),''),nullif(trim(coalesce(p_country,'')),''),nullif(trim(coalesce(p_region,'')),''),encode(digest(v_token,'sha256'),'hex'),auth.uid()) returning id into v_id;
  return jsonb_build_object('id',v_id,'token',v_token,'email',v_email,'kind',p_kind,'expires_at',now()+interval '7 days');
end;
$function$;
