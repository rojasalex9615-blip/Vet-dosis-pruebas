-- LOCAL CANDIDATE: apply only with the coordinated permission cutover. No clinical protocol is seeded.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional) values
 ('hospital.isolation.manage','Indicar o retirar aislamiento hospitalario',false,true),
 ('hospital.isolation.handle','Registrar acceso a aislamiento y desinfección',false,false);
-- Existing administrative audit access must not expose these new clinical events without hospital.read.
create policy hospital_isolation_audit_read on public.audit_log as restrictive for select to authenticated
 using(action not in ('hospital_isolation_changed','hospital_isolation_entry','hospital_isolation_cleaning_due','hospital_isolation_cleaned')
 or private.hospital_readable(clinic_id));
create table private.hospital_isolations (
 clinic_id uuid not null,stay_id uuid primary key,active boolean not null,
 protocol_reference text not null check(length(btrim(protocol_reference)) between 1 and 1000),
 steps jsonb not null check(jsonb_typeof(steps)='array' and jsonb_array_length(steps) between 1 and 30),
 reason text not null,changed_by uuid not null references auth.users(id),changed_at timestamptz not null,
 foreign key(clinic_id,stay_id) references public.hospital_stays(clinic_id,id)
);
create table private.hospital_isolation_areas (
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null,stay_id uuid not null,cage text,
 protocol_reference text not null,steps jsonb not null,
 exposed_at timestamptz not null default clock_timestamp(),released_at timestamptz,
 cleaned_at timestamptz,cleaned_by uuid references auth.users(id),cleaning_notes text,checks jsonb,
 foreign key(clinic_id,stay_id) references public.hospital_stays(clinic_id,id),
 check((cleaned_at is null)=(cleaned_by is null)),check(cleaned_at is null or released_at is not null)
);
create unique index hospital_isolation_current_area on private.hospital_isolation_areas(stay_id) where released_at is null;
create index hospital_isolation_dirty_cage on private.hospital_isolation_areas(clinic_id,lower(btrim(cage))) where cleaned_at is null;
alter table private.hospital_isolations enable row level security;
alter table private.hospital_isolation_areas enable row level security;
revoke all on private.hospital_isolations,private.hospital_isolation_areas from public,anon,authenticated,service_role;

-- All hospital writers, including old admission/location paths, honor pending cleaning.
create function private.hospital_isolation_location_guard() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform 1 from public.clinics where id=new.clinic_id for update;
 if new.discharged_at is null and new.cage is not null and
    (tg_op='INSERT' or lower(btrim(new.cage)) is distinct from lower(btrim(old.cage))) and exists(
    select 1 from private.hospital_isolation_areas a where a.clinic_id=new.clinic_id
    and lower(btrim(a.cage))=lower(btrim(new.cage)) and a.released_at is not null and a.cleaned_at is null
 ) then raise exception 'isolation_cleaning_required';end if;
 return new;
end$$;
create trigger hospital_isolation_location_guard before insert or update on public.hospital_stays
 for each row execute function private.hospital_isolation_location_guard();
create function private.hospital_isolation_location_changed() returns trigger language plpgsql security definer set search_path='' as $$
declare config private.hospital_isolations;a uuid;begin
 if old.discharged_at is null and (new.discharged_at is not null or lower(btrim(new.cage)) is distinct from lower(btrim(old.cage))) then
  for a in update private.hospital_isolation_areas set released_at=clock_timestamp()
   where stay_id=new.id and released_at is null returning id loop
   insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(new.clinic_id,auth.uid(),'hospital_isolation_cleaning_due',new.id,jsonb_build_object('area_id',a,'cage',old.cage));
  end loop;
  select * into config from private.hospital_isolations where stay_id=new.id and active;
  if found and new.discharged_at is null then
   insert into private.hospital_isolation_areas(clinic_id,stay_id,cage,protocol_reference,steps)
    values(new.clinic_id,new.id,new.cage,config.protocol_reference,config.steps);
  end if;
 end if;
 return new;
end$$;
create trigger hospital_isolation_location_changed after update on public.hospital_stays
 for each row execute function private.hospital_isolation_location_changed();
revoke all on function private.hospital_isolation_location_guard(),private.hospital_isolation_location_changed() from public,anon,authenticated,service_role;

create function public.hospital_isolation_set(p_clinic uuid,p_stay uuid,p_version integer,p_active boolean,p_reason text,p_reference text,p_steps jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.hospital_stays;config private.hospital_isolations;g uuid;fp jsonb;receipt uuid;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 g=private.hospital_order_permission(p_clinic,'hospital.isolation.manage',null,true);
 p_reference=btrim(p_reference);
 if p_active is null or coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'isolation_reason_required';end if;
 fp=jsonb_build_object('kind','isolation_set','stay',p_stay,'version',p_version,'active',p_active,'reason',p_reason,'reference',p_reference,'steps',p_steps);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);if receipt is not null then return receipt;end if;
 select * into s from public.hospital_stays where clinic_id=p_clinic and id=p_stay for update;
 if not found or s.discharged_at is not null then raise exception 'stay_inactive';end if;
 g=private.hospital_order_permission(p_clinic,'hospital.isolation.manage',null,true);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 if s.version is distinct from p_version then raise exception 'hospital_version_conflict';end if;
 select * into config from private.hospital_isolations where stay_id=p_stay;
 if found then
  if config.active=p_active then raise exception 'isolation_state_unchanged';end if;
  if p_reference is distinct from config.protocol_reference or p_steps is distinct from config.steps then raise exception 'isolation_protocol_snapshot_immutable';end if;
 else
  if not p_active then raise exception 'isolation_not_active';end if;
  if coalesce(length(btrim(p_reference)),0) not between 1 and 1000 or jsonb_typeof(p_steps) is distinct from 'array' then raise exception 'isolation_protocol_required';end if;
  if jsonb_array_length(p_steps) not between 1 and 30 then raise exception 'isolation_protocol_required';end if;
  if exists(select 1 from jsonb_array_elements(p_steps) step where jsonb_typeof(step)<>'string' or (step#>>'{}') is distinct from btrim(step#>>'{}') or length(btrim(step#>>'{}')) not between 1 and 500)
   or (select count(distinct btrim(step#>>'{}')) from jsonb_array_elements(p_steps) step)<>jsonb_array_length(p_steps) then raise exception 'isolation_steps_invalid';end if;
 end if;
 insert into private.hospital_isolations values(p_clinic,p_stay,p_active,p_reference,p_steps,btrim(p_reason),auth.uid(),clock_timestamp())
 on conflict(stay_id) do update set active=excluded.active,reason=excluded.reason,changed_by=excluded.changed_by,changed_at=excluded.changed_at;
 update public.hospital_stays set version=version+1 where id=p_stay;
 if p_active and not exists(select 1 from private.hospital_isolation_areas where stay_id=p_stay and released_at is null) then
  insert into private.hospital_isolation_areas(clinic_id,stay_id,cage,protocol_reference,steps) values(p_clinic,p_stay,s.cage,p_reference,p_steps);
 end if;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'hospital_isolation_changed',p_stay,jsonb_build_object('active',p_active,'reason',p_reason,'reference',p_reference,'steps',p_steps,'permission_grant_id',g,'version',s.version+1));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,p_stay);return p_stay;
end$$;

create function public.hospital_isolation_enter(p_clinic uuid,p_stay uuid,p_version integer,p_note text,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.hospital_stays;g uuid;fp jsonb;receipt uuid;event_id uuid;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 g=private.hospital_order_permission(p_clinic,'hospital.isolation.handle',null,false);
 if coalesce(length(btrim(p_note)),0) not between 1 and 1000 then raise exception 'isolation_entry_note_required';end if;
 fp=jsonb_build_object('kind','isolation_enter','stay',p_stay,'version',p_version,'note',p_note);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);if receipt is not null then return receipt;end if;
 select * into s from public.hospital_stays where clinic_id=p_clinic and id=p_stay for update;
 if not found or s.discharged_at is not null or not exists(select 1 from private.hospital_isolations where stay_id=p_stay and active) then raise exception 'isolation_not_active';end if;
 g=private.hospital_order_permission(p_clinic,'hospital.isolation.handle',null,false);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 if s.version is distinct from p_version then raise exception 'hospital_version_conflict';end if;
 event_id=gen_random_uuid();
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'hospital_isolation_entry',p_stay,jsonb_build_object('event_id',event_id,'note',p_note,'permission_grant_id',g,'cage',s.cage,'version',s.version));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,event_id);return event_id;
end$$;

create function public.hospital_isolation_clean(p_clinic uuid,p_area uuid,p_checks jsonb,p_notes text,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare a private.hospital_isolation_areas;g uuid;fp jsonb;receipt uuid;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 g=private.hospital_order_permission(p_clinic,'hospital.isolation.handle',null,false);
 fp=jsonb_build_object('kind','isolation_clean','area',p_area,'checks',p_checks,'notes',p_notes);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);if receipt is not null then return receipt;end if;
 select * into a from private.hospital_isolation_areas where clinic_id=p_clinic and id=p_area for update;
 if not found then raise exception 'isolation_area_not_found';end if;
 g=private.hospital_order_permission(p_clinic,'hospital.isolation.handle',null,false);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 if a.released_at is null or a.cleaned_at is not null then raise exception 'isolation_area_not_released';end if;
 if p_checks is distinct from a.steps or p_notes is null or length(p_notes)>1000 then raise exception 'isolation_checklist_incomplete';end if;
 update private.hospital_isolation_areas set cleaned_at=clock_timestamp(),cleaned_by=auth.uid(),checks=p_checks,cleaning_notes=p_notes where id=a.id;
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,auth.uid(),'hospital_isolation_cleaned',a.stay_id,jsonb_build_object('area_id',a.id,'cage',a.cage,'reference',a.protocol_reference,'checks',p_checks,'notes',p_notes,'permission_grant_id',g));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,a.id);return a.id;
end$$;
create function public.hospital_isolation_history(p_clinic uuid,p_stay uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 if not private.hospital_readable(p_clinic) then raise exception 'explicit_permission_required';end if;
 if p_stay is not null and not exists(select 1 from public.hospital_stays where clinic_id=p_clinic and id=p_stay) then raise exception 'hospital_stay_not_found';end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('stay_id',a.entity_id,'patient_name',p.name,'actor_id',a.actor_id,'at',a.occurred_at,'action',a.action,'details',a.details) order by a.occurred_at,a.id),'[]') from public.audit_log a join public.hospital_stays s on s.id::text=a.entity_id and s.clinic_id=a.clinic_id join public.vet_patients p on p.id=s.patient_id and p.clinic_id=s.clinic_id where a.clinic_id=p_clinic and (p_stay is null or a.entity_id=p_stay::text) and a.action in ('hospital_isolation_changed','hospital_isolation_entry','hospital_isolation_cleaning_due','hospital_isolation_cleaned'));
end$$;

alter function public.hospital_snapshot(uuid) set schema private;
alter function private.hospital_snapshot(uuid) rename to hospital_snapshot_before_isolation;
revoke all on function private.hospital_snapshot_before_isolation(uuid) from public,anon,authenticated,service_role;
create function public.hospital_snapshot(p_clinic_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b jsonb;begin
 b=private.hospital_snapshot_before_isolation(p_clinic_id);
 return b||jsonb_build_object('capabilities',(b->'capabilities')||jsonb_build_object('isolation_version',1),
 'permissions',(b->'permissions')||jsonb_build_object(
 'hospital.isolation.manage',private.professional_current(p_clinic_id,auth.uid()) and private.permission_effective(p_clinic_id,auth.uid(),'hospital.isolation.manage') is not null,
 'hospital.isolation.handle',private.permission_effective(p_clinic_id,auth.uid(),'hospital.isolation.handle') is not null),
 'isolations',(select coalesce(jsonb_agg(to_jsonb(i)),'[]') from private.hospital_isolations i join public.hospital_stays s on s.id=i.stay_id and s.clinic_id=i.clinic_id where i.clinic_id=p_clinic_id and s.discharged_at is null),
 'isolation_areas',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('patient_name',p.name) order by a.exposed_at,a.id),'[]') from private.hospital_isolation_areas a join public.hospital_stays s on s.id=a.stay_id and s.clinic_id=a.clinic_id join public.vet_patients p on p.id=s.patient_id and p.clinic_id=s.clinic_id where a.clinic_id=p_clinic_id and a.cleaned_at is null));
end$$;
revoke all on function public.hospital_snapshot(uuid),public.hospital_isolation_set(uuid,uuid,integer,boolean,text,text,jsonb,text),public.hospital_isolation_enter(uuid,uuid,integer,text,text),public.hospital_isolation_clean(uuid,uuid,jsonb,text,text),public.hospital_isolation_history(uuid,uuid) from public,anon;
grant execute on function public.hospital_snapshot(uuid),public.hospital_isolation_set(uuid,uuid,integer,boolean,text,text,jsonb,text),public.hospital_isolation_enter(uuid,uuid,integer,text,text),public.hospital_isolation_clean(uuid,uuid,jsonb,text,text),public.hospital_isolation_history(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
