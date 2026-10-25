-- LOCAL CANDIDATE ONLY, after 14D. No clinical defaults or remote deployment.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
create table private.hospital_care_results (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null references public.clinics(id),
 task_id uuid not null references public.hospital_tasks(id),
 care_kind text not null check(care_kind in ('feeding','catheter_review','equipment_change','other')),
 offered numeric,consumed numeric,unit text,
 findings text not null check(length(btrim(findings)) between 1 and 4000),
 observed_at timestamptz not null,
 actor_id uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 procedure_grant_id uuid not null references private.member_permission_grants(id),
 replaces_id uuid unique references private.hospital_care_results(id),
 correction_reason text,
 check((care_kind='feeding' and offered is not null and consumed is not null and unit is not null and offered>0 and consumed>=0 and consumed<=offered and unit in ('g','ml','porción'))
 or (care_kind<>'feeding' and offered is null and consumed is null and unit is null)),
 check((replaces_id is null and correction_reason is null) or (replaces_id is not null and correction_reason is not null and length(btrim(correction_reason)) between 1 and 1000))
);
create unique index hospital_care_first_result on private.hospital_care_results(task_id) where replaces_id is null;
alter table private.hospital_care_results enable row level security;
revoke all on private.hospital_care_results from public,anon,authenticated,service_role;
create trigger immutable before update or delete on private.hospital_care_results for each row execute function private.permission_immutable();

create function public.hospital_care_workspace(p_clinic uuid,p_task uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare t public.hospital_tasks;s public.hospital_stays;eligible boolean=false;has_result boolean=false;
begin
 if not private.hospital_readable(p_clinic) or not exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(p_clinic,auth.uid(),'hospital.read') and g.valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 if p_task is not null then
 select * into t from public.hospital_tasks where id=p_task and clinic_id=p_clinic;
 if not found then raise exception 'task_not_found';end if;
 select * into s from public.hospital_stays where id=t.stay_id and clinic_id=p_clinic;
 has_result=exists(select 1 from private.hospital_care_results where task_id=t.id);
 eligible=t.kind='revision' and t.prescription_item_id is null and t.medication_record_id is null and t.procedure_type_id is not null and t.authority_grant_id is not null
 and private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp())
 and exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(p_clinic,auth.uid(),'procedure.perform',t.procedure_type_id) and g.valid_until>clock_timestamp())
 and ((t.state='pending' and s.discharged_at is null and t.due_at<=clock_timestamp() and (t.snoozed_until is null or t.snoozed_until<=clock_timestamp())) or (t.state='done' and t.performed_by=auth.uid()));
 end if;
 return jsonb_build_object('schema_version',1,'clinic_id',p_clinic,'actor_id',auth.uid(),'task_id',p_task,
 'task',case when p_task is null then null else to_jsonb(t)||jsonb_build_object('patient_id',s.patient_id,'patient_name',(select name from public.vet_patients where id=s.patient_id and clinic_id=p_clinic)) end,
 'actions',jsonb_build_object('record',eligible and not has_result,'correct',eligible and has_result),
 'records',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('offered',r.offered::text,'consumed',r.consumed::text,'patient_id',s2.patient_id,'patient_name',p.name,'task_label',t2.label) order by r.observed_at desc,r.created_at desc,r.id),'[]')
 from private.hospital_care_results r join public.hospital_tasks t2 on t2.id=r.task_id and t2.clinic_id=r.clinic_id join public.hospital_stays s2 on s2.id=t2.stay_id and s2.clinic_id=r.clinic_id join public.vet_patients p on p.id=s2.patient_id and p.clinic_id=r.clinic_id
 where r.clinic_id=p_clinic and (p_task is null or r.task_id=p_task)));
end$$;

create function public.hospital_care_record(p_clinic uuid,p_task uuid,p_version integer,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare t public.hospital_tasks;s public.hospital_stays;g uuid;previous uuid;at_time timestamptz;fp jsonb;receipt uuid;k text;
begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 select * into t from public.hospital_tasks where id=p_task and clinic_id=p_clinic;
 if not found then raise exception 'task_not_found';end if;
 select * into s from public.hospital_stays where id=t.stay_id and clinic_id=p_clinic for update;
 select * into t from public.hospital_tasks where id=p_task and clinic_id=p_clinic for update;
 if t.kind<>'revision' or t.prescription_item_id is not null or t.medication_record_id is not null or t.procedure_type_id is null or t.authority_grant_id is null then raise exception 'typed_review_required';end if;
 g=private.hospital_order_permission(p_clinic,'procedure.perform',t.procedure_type_id,true);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_care_result';end if;
 if exists(select 1 from jsonb_object_keys(p_data) key where key not in ('care_kind','findings','observed_at','offered','consumed','unit','confirmed','replaces_id','correction_reason')) then raise exception 'care_result_fields_only';end if;
 if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'care_confirmation_required';end if;
 foreach k in array array['care_kind','findings','observed_at'] loop
 if jsonb_typeof(p_data->k) is distinct from 'string' then raise exception 'invalid_care_result';end if;end loop;
 foreach k in array array['replaces_id','correction_reason','offered','consumed','unit'] loop
 if p_data ? k and jsonb_typeof(p_data->k) is distinct from 'string' then raise exception 'invalid_care_result';end if;end loop;
 at_time=private.clinical_time(p_data->>'observed_at');
 if at_time>clock_timestamp() or at_time<s.admitted_at or at_time<t.due_at or (t.snoozed_until is not null and at_time<t.snoozed_until) or (t.performed_at is not null and at_time>t.performed_at) then raise exception 'invalid_care_observation_time';end if;
 if not private.clinical_professional_at(p_clinic,auth.uid(),at_time) or not exists(select 1 from private.member_permission_grants where id=g and granted_at<=at_time and valid_until>at_time) then raise exception 'care_observation_authority_required';end if;
 previous=(p_data->>'replaces_id')::uuid;
 if previous is not null and not exists(select 1 from private.hospital_care_results where id=previous and task_id=t.id and clinic_id=p_clinic and actor_id=auth.uid()) then raise exception 'own_care_correction_required';end if;
 if previous is null and p_data ? 'correction_reason' then raise exception 'invalid_care_result';end if;
 fp=jsonb_build_object('kind','hospital_care_result','task',p_task,'version',p_version,'data',p_data);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);if receipt is not null then return receipt;end if;
 if t.version is distinct from p_version then raise exception 'task_version_conflict';end if;
 if t.state='cancelled' then raise exception 'task_not_pending';end if;
 if t.state='done' and t.performed_by is distinct from auth.uid() then raise exception 'own_care_result_only';end if;
 if previous is not null and exists(select 1 from private.hospital_care_results where replaces_id=previous) then raise exception 'care_result_already_corrected';end if;
 if previous is null and exists(select 1 from private.hospital_care_results where task_id=t.id) then raise exception 'care_result_already_recorded';end if;
 if p_data->>'care_kind'='feeding' then
 foreach k in array array['offered','consumed'] loop
 if coalesce(p_data->>k,'') !~ '^\d{1,12}(\.\d{1,9})?$' then raise exception 'exact_care_quantity_required';end if;end loop;
 elsif p_data ? 'offered' or p_data ? 'consumed' or p_data ? 'unit' then raise exception 'feeding_fields_only';end if;
 if t.state='pending' then
 -- Existing contract validates due time, snooze, active stay and current authority again.
 perform public.hospital_task_action(p_clinic,t.id,t.version,'perform');
 end if;
 insert into private.hospital_care_results(clinic_id,task_id,care_kind,offered,consumed,unit,findings,observed_at,actor_id,procedure_grant_id,replaces_id,correction_reason)
 values(p_clinic,t.id,p_data->>'care_kind',(p_data->>'offered')::numeric,(p_data->>'consumed')::numeric,p_data->>'unit',btrim(p_data->>'findings'),at_time,auth.uid(),g,previous,p_data->>'correction_reason') returning id into receipt;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,receipt);
 perform private.permission_event(p_clinic,'hospital_care_result_added',receipt,jsonb_build_object('task_id',t.id,'permission_grant_id',g,'replaces_id',previous));
 return receipt;
end$$;

alter function public.hospital_snapshot(uuid) set schema private;
alter function private.hospital_snapshot(uuid) rename to hospital_snapshot_before_care_results;
revoke all on function private.hospital_snapshot_before_care_results(uuid) from public,anon,authenticated,service_role;
create function public.hospital_snapshot(p_clinic_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b jsonb;begin
 b=private.hospital_snapshot_before_care_results(p_clinic_id);
 return b||jsonb_build_object('capabilities',(b->'capabilities')||jsonb_build_object('care_results_version',1));
end$$;
revoke all on function public.hospital_snapshot(uuid),public.hospital_care_workspace(uuid,uuid),public.hospital_care_record(uuid,uuid,integer,jsonb,text) from public,anon,service_role;
grant execute on function public.hospital_snapshot(uuid),public.hospital_care_workspace(uuid,uuid),public.hospital_care_record(uuid,uuid,integer,jsonb,text) to authenticated;
select private.beta_install_guards();
notify pgrst,'reload schema';
commit;
