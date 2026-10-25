-- Read-only local candidate after 14H and its dependencies. No remote activation.
begin;
create index hospital_closed_history on public.hospital_stays(clinic_id,discharged_at desc,id desc) where discharged_at is not null;
create index hospital_task_history on public.hospital_tasks(clinic_id,stay_id,due_at,id);
create function public.hospital_closed_history(p_clinic uuid,p_query text default '',p_before jsonb default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;cursor_at timestamptz;cursor_id uuid;begin
 if not private.hospital_readable(p_clinic) or not exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(p_clinic,auth.uid(),'hospital.read') and g.valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 if p_query is null or length(p_query)>100 then raise exception 'invalid_history_query';end if;
 if p_before is not null then
 if jsonb_typeof(p_before)<>'object' or not(p_before ?& array['at','id']) or (select count(*) from jsonb_object_keys(p_before))<>2 then raise exception 'invalid_history_cursor';end if;
 cursor_at=(p_before->>'at')::timestamptz;cursor_id=(p_before->>'id')::uuid;
 if cursor_at is null or cursor_id is null then raise exception 'invalid_history_cursor';end if;
 end if;
 with page as (
 select s.*,p.name patient_name,p.species from public.hospital_stays s join public.vet_patients p on p.id=s.patient_id and p.clinic_id=s.clinic_id
 where s.clinic_id=p_clinic and s.discharged_at is not null
 and (cursor_at is null or (s.discharged_at,s.id)<(cursor_at,cursor_id))
 and (p_query='' or position(lower(btrim(p_query)) in lower(p.name))>0)
 order by s.discharged_at desc,s.id desc limit 26
 ), visible as (select * from page order by discharged_at desc,id desc limit 25)
 select jsonb_build_object('version',1,'clinic_id',p_clinic,'actor_id',auth.uid(),'query',p_query,
 'stays',coalesce((select jsonb_agg(jsonb_build_object('id',id,'clinic_id',clinic_id,'patient_id',patient_id,'patient_name',patient_name,'species',species,'cage',cage,'admitted_at',admitted_at,'discharged_at',discharged_at,'discharged_by',discharged_by,'discharge_reason',discharge_reason) order by discharged_at desc,id desc) from visible),'[]'),
 'next',case when (select count(*) from page)>25 then (select jsonb_build_object('at',discharged_at,'id',id) from visible order by discharged_at,id limit 1) else null end) into result;
 return result;
end$$;
create function public.hospital_closed_detail(p_clinic uuid,p_stay uuid,p_before jsonb default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare s public.hospital_stays;cursor_at timestamptz;cursor_id uuid;tasks jsonb;next_page jsonb;begin
 if not private.hospital_readable(p_clinic) or not exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(p_clinic,auth.uid(),'hospital.read') and g.valid_until>clock_timestamp()) then raise exception 'explicit_permission_required';end if;
 select * into s from public.hospital_stays where clinic_id=p_clinic and id=p_stay and discharged_at is not null;
 if not found then raise exception 'closed_stay_not_found';end if;
 if p_before is not null then
 if jsonb_typeof(p_before)<>'object' or not(p_before ?& array['at','id']) or (select count(*) from jsonb_object_keys(p_before))<>2 then raise exception 'invalid_history_cursor';end if;
 cursor_at=(p_before->>'at')::timestamptz;cursor_id=(p_before->>'id')::uuid;
 if cursor_at is null or cursor_id is null then raise exception 'invalid_history_cursor';end if;
 end if;
 with page as (
 select t.* from public.hospital_tasks t where t.clinic_id=p_clinic and t.stay_id=s.id and (cursor_at is null or (t.due_at,t.id)>(cursor_at,cursor_id)) order by t.due_at,t.id limit 51
 ), visible as (select * from page order by due_at,id limit 50)
 select coalesce((select jsonb_agg((to_jsonb(t)-'actions')||jsonb_build_object(
 'performed_name',(select name from public.staff_display_names where clinic_id=p_clinic and user_id=t.performed_by),
 'cancelled_name',(select name from public.staff_display_names where clinic_id=p_clinic and user_id=t.cancelled_by)) order by t.due_at,t.id) from visible t),'[]'),
 case when (select count(*) from page)>50 then (select jsonb_build_object('at',due_at,'id',id) from visible order by due_at desc,id desc limit 1) else null end into tasks,next_page;
 return jsonb_build_object('version',1,'clinic_id',p_clinic,'actor_id',auth.uid(),'stay_id',p_stay,
 'stay',to_jsonb(s)||jsonb_build_object('patient_name',(select name from public.vet_patients where clinic_id=p_clinic and id=s.patient_id),'species',(select species from public.vet_patients where clinic_id=p_clinic and id=s.patient_id),
 'admitted_name',(select name from public.staff_display_names where clinic_id=p_clinic and user_id=s.admitted_by),
 'discharged_name',(select name from public.staff_display_names where clinic_id=p_clinic and user_id=s.discharged_by)),
 'events',public.hospital_cage_history(p_clinic,s.id),
 'tasks',tasks,'next',next_page);
end$$;
revoke all on function public.hospital_closed_history(uuid,text,jsonb),public.hospital_closed_detail(uuid,uuid,jsonb) from public,anon,service_role;
grant execute on function public.hospital_closed_history(uuid,text,jsonb),public.hospital_closed_detail(uuid,uuid,jsonb) to authenticated;
commit;
