-- Local candidate after 14F. Scheduler activation is a separate operator step.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional)
values('hospital.automation.manage','Configurar responsables de avisos hospitalarios',false,false);
create table private.hospital_automation_runtime(singleton boolean primary key default true check(singleton),enabled boolean not null default false,last_run_at timestamptz);
insert into private.hospital_automation_runtime default values;
create table private.hospital_notice_routes(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 primary_user uuid not null references auth.users(id),mvz_user uuid not null references auth.users(id),
 primary_member_since timestamptz not null,mvz_member_since timestamptz not null,
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 check(primary_user<>mvz_user)
);
create table private.hospital_daily_orders(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),
 stay_id uuid not null,procedure_id uuid not null,author_id uuid not null references auth.users(id),
 schedule_grant uuid not null references private.member_permission_grants(id),read_grant uuid not null references private.member_permission_grants(id),
 label text not null check(length(btrim(label)) between 1 and 300),instructions text not null check(length(btrim(instructions)) between 1 and 4000),
 first_day date not null,last_day date not null,zone text not null,minutes integer[] not null,
 escalation_minutes integer not null check(escalation_minutes between 1 and 120),
 created_at timestamptz not null default clock_timestamp(),replaces_id uuid unique references private.hospital_daily_orders(id),version integer not null check(version>0),
 foreign key(clinic_id,stay_id) references public.hospital_stays(clinic_id,id),
 foreign key(clinic_id,procedure_id) references private.procedure_types(clinic_id,id),
 check(last_day>=first_day and last_day-first_day<31 and cardinality(minutes)>0 and cardinality(minutes)*(last_day-first_day+1)<=200)
);
create table private.hospital_order_stops(
 order_id uuid primary key references private.hospital_daily_orders(id),clinic_id uuid not null references public.clinics(id),
 kind text not null check(kind in ('manual','replaced','authority_lost','discharged')),
 reason text not null check(length(btrim(reason)) between 1 and 1000),actor_id uuid references auth.users(id),created_at timestamptz not null default clock_timestamp()
);
alter table public.hospital_tasks add column daily_order_id uuid references private.hospital_daily_orders(id);
create unique index hospital_daily_task_once on public.hospital_tasks(daily_order_id,due_at) where daily_order_id is not null;
create table private.hospital_notices(
 id uuid primary key default gen_random_uuid(),clinic_id uuid not null references public.clinics(id),task_id uuid not null references public.hospital_tasks(id),
 route_id uuid not null references private.hospital_notice_routes(id),stage text not null check(stage in ('primary','mvz')),
 recipient_id uuid not null references auth.users(id),member_since timestamptz not null,created_at timestamptz not null default clock_timestamp(),
 unique(task_id,stage,recipient_id,member_since)
);
create table private.hospital_notice_responses(
 notice_id uuid primary key references private.hospital_notices(id),clinic_id uuid not null references public.clinics(id),
 actor_id uuid not null references auth.users(id),note text not null check(length(btrim(note)) between 1 and 1000),created_at timestamptz not null default clock_timestamp()
);
do $$declare t text;begin
 foreach t in array array['hospital_automation_runtime','hospital_notice_routes','hospital_daily_orders','hospital_order_stops','hospital_notices','hospital_notice_responses'] loop
 execute format('alter table private.%I enable row level security',t);
 execute format('revoke all on private.%I from public,anon,authenticated,service_role',t);
 if t<>'hospital_automation_runtime' then execute format('create trigger immutable before update or delete on private.%I for each row execute function private.permission_immutable()',t);end if;
 end loop;
end$$;
-- Reject nonexistent AND ambiguous local times. Derive candidate offsets around each date,
-- including fractional-hour offsets; never use the device or server session time zone.
create function private.hospital_wall_time(p_day date,p_minute integer,p_zone text) returns timestamptz
language plpgsql stable set search_path='' as $$
declare wall timestamp;result timestamptz;n integer;begin
 if p_minute is null or p_minute not between 0 and 1439 or not exists(select 1 from pg_timezone_names where name=p_zone) then raise exception 'invalid_hospital_zone_or_time';end if;
 wall=p_day::timestamp+make_interval(mins=>p_minute);
 select count(*),min(candidate) into n,result from (
 select distinct (wall-offset_value) at time zone 'UTC' as candidate from (
 select distinct (sample at time zone p_zone)-(sample at time zone 'UTC') as offset_value
 from generate_series((wall at time zone 'UTC')-interval '2 days',(wall at time zone 'UTC')+interval '2 days',interval '1 hour') sample
 ) offsets
 ) candidates where candidate at time zone p_zone=wall;
 if n<>1 then raise exception 'ambiguous_or_missing_hospital_time';end if;
 return result;
end$$;
create function private.hospital_order_times(p_data jsonb) returns table(due timestamptz)
language plpgsql stable set search_path='' as $$
declare a date;b date;m integer;mins integer[];d date;zone text;begin
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_daily_order';end if;
 if (p_data->>'first_day') !~ '^\d{4}-\d{2}-\d{2}$' or (p_data->>'last_day') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'invalid_order_dates';end if;
 a=(p_data->>'first_day')::date;b=(p_data->>'last_day')::date;zone=p_data->>'zone';
 if a is null or b is null or b<a or b-a>=31 or not exists(select 1 from pg_timezone_names where name=zone) or a>(clock_timestamp() at time zone zone)::date+366 then raise exception 'invalid_order_dates_or_zone';end if;
 if jsonb_typeof(p_data->'minutes') is distinct from 'array' then raise exception 'explicit_daily_times_required';end if;
 if exists(select 1 from jsonb_array_elements(p_data->'minutes') x where jsonb_typeof(x)<>'number' or x::text !~ '^\d{1,4}$') then raise exception 'invalid_daily_times';end if;
 select array_agg(x::text::integer order by x::text::integer) into mins from jsonb_array_elements(p_data->'minutes') x;
 if cardinality(mins) is null or cardinality(mins)*(b-a+1)>200 or cardinality(mins)<>(select count(distinct x) from unnest(mins) x) then raise exception 'invalid_daily_times';end if;
 d=a;while d<=b loop
 foreach m in array mins loop due=private.hospital_wall_time(d,m,zone);return next;end loop;
 d=d+1;end loop;
end$$;
create function private.hospital_notice_recipient(p_clinic uuid,p_user uuid,p_since timestamptz,p_mvz boolean) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=p_user and created_at=p_since)
 and exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(p_clinic,p_user,'hospital.read') and g.valid_until>clock_timestamp())
 and exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(p_clinic,p_user,'hospital.report') and g.valid_until>clock_timestamp())
 and (not p_mvz or (private.clinical_professional_at(p_clinic,p_user,clock_timestamp()) and exists(
 select 1 from private.clinic_responsible_designations d where d.clinic_id=p_clinic and d.user_id=p_user and d.member_since=p_since and d.accepted_at is not null and d.revoked_at is null and d.valid_until>clock_timestamp())));
$$;
create function private.hospital_order_stop(p_order uuid,p_kind text,p_reason text,p_actor uuid) returns void
language plpgsql security definer set search_path='' as $$
declare o private.hospital_daily_orders;begin
 select * into o from private.hospital_daily_orders where id=p_order;
 insert into private.hospital_order_stops(order_id,clinic_id,kind,reason,actor_id) values(o.id,o.clinic_id,p_kind,p_reason,p_actor);
 -- Preserve due/past reviews for an explicit clinical resolution. Never cancel medications.
 update public.hospital_tasks set state='cancelled',cancelled_by=p_actor,cancelled_at=clock_timestamp(),cancel_reason=p_reason,version=version+1
 where daily_order_id=o.id and state='pending' and due_at>clock_timestamp();
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(o.clinic_id,p_actor,'hospital_daily_order_stopped',o.id,jsonb_build_object('kind',p_kind,'reason',p_reason));
end$$;
create function private.hospital_automation_clinic(p_clinic uuid) returns void
language plpgsql security definer set search_path='' as $$
declare o private.hospital_daily_orders;s public.hospital_stays;r private.hospital_notice_routes;t public.hospital_tasks;instant timestamptz;task uuid;g uuid;cutoff date;begin
 if not(select enabled from private.hospital_automation_runtime) then return;end if;
 perform private.medication_lock(p_clinic);
 if not(select enabled from private.hospital_automation_runtime) then return;end if;
 for o in select d.* from private.hospital_daily_orders d where d.clinic_id=p_clinic and not exists(select 1 from private.hospital_order_stops x where x.order_id=d.id) order by d.created_at,d.id loop
 select * into s from public.hospital_stays where id=o.stay_id and clinic_id=p_clinic for update;
 if s.discharged_at is not null then perform private.hospital_order_stop(o.id,'discharged','Alta registrada en servidor',null);continue;end if;
 -- The grant originally signing the order must remain current; no automatic reauthorization.
 perform pg_advisory_xact_lock(hashtextextended(o.author_id::text,9061));
 if not private.clinical_professional_at(p_clinic,o.author_id,clock_timestamp())
 or not exists(select 1 from private.member_permission_grants g2 join public.clinic_members m on m.clinic_id=g2.clinic_id and m.user_id=g2.user_id and m.created_at=g2.member_since where g2.id=o.schedule_grant and g2.valid_until>clock_timestamp() and not exists(select 1 from private.permission_revocations x where x.grant_id=g2.id))
 or not exists(select 1 from private.member_permission_grants g2 join public.clinic_members m on m.clinic_id=g2.clinic_id and m.user_id=g2.user_id and m.created_at=g2.member_since where g2.id=o.read_grant and g2.valid_until>clock_timestamp() and not exists(select 1 from private.permission_revocations x where x.grant_id=g2.id))
 or not exists(select 1 from private.procedure_types where id=o.procedure_id and clinic_id=p_clinic and active) then
 perform private.hospital_order_stop(o.id,'authority_lost','Orden detenida: autorización o procedimiento ya no vigente',null);continue;end if;
 cutoff=(clock_timestamp() at time zone o.zone)::date+1;
 for instant in select due from private.hospital_order_times(jsonb_build_object('first_day',o.first_day,'last_day',o.last_day,'zone',o.zone,'minutes',to_jsonb(o.minutes))) loop
 if instant at time zone o.zone>= (cutoff+1)::timestamp or instant<=o.created_at then continue;end if;
 insert into public.hospital_tasks(clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,procedure_type_id,authority_grant_id,daily_order_id)
 values(p_clinic,o.stay_id,'revision',o.label,o.instructions,instant,o.escalation_minutes,o.author_id,o.procedure_id,o.schedule_grant,o.id)
 on conflict(daily_order_id,due_at) where daily_order_id is not null do nothing returning id into task;
 if task is not null then insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(p_clinic,null,'hospital_daily_task_generated',task,jsonb_build_object('order_id',o.id,'order_author_id',o.author_id,'order_version',o.version,'permission_grant_id',o.schedule_grant));end if;
 end loop;
 end loop;
 select * into r from private.hospital_notice_routes where clinic_id=p_clinic order by created_at desc,id desc limit 1;
 if not found then return;end if;
 for t in select t2.* from public.hospital_tasks t2 join public.hospital_stays s2 on s2.id=t2.stay_id and s2.clinic_id=t2.clinic_id
 where t2.clinic_id=p_clinic and t2.state='pending' and s2.discharged_at is null and t2.due_at<=clock_timestamp() and (t2.snoozed_until is null or t2.snoozed_until<=clock_timestamp()) order by t2.due_at,t2.id loop
 if private.hospital_notice_recipient(p_clinic,r.primary_user,r.primary_member_since,false) then
 insert into private.hospital_notices(clinic_id,task_id,route_id,stage,recipient_id,member_since) values(p_clinic,t.id,r.id,'primary',r.primary_user,r.primary_member_since) on conflict(task_id,stage,recipient_id,member_since) do nothing;
 end if;
 if t.due_at+make_interval(mins=>t.escalation_minutes)<=clock_timestamp()
 and not exists(select 1 from private.hospital_notice_responses a join private.hospital_notices n on n.id=a.notice_id where n.task_id=t.id)
 and private.hospital_notice_recipient(p_clinic,r.mvz_user,r.mvz_member_since,true) then
 insert into private.hospital_notices(clinic_id,task_id,route_id,stage,recipient_id,member_since) values(p_clinic,t.id,r.id,'mvz',r.mvz_user,r.mvz_member_since) on conflict(task_id,stage,recipient_id,member_since) do nothing;
 end if;
 end loop;
end$$;
create function private.hospital_automation_tick() returns void language plpgsql security definer set search_path='' as $$
declare c uuid;begin
 if not(select enabled from private.hospital_automation_runtime) then return;end if;
 for c in select clinic_id from public.hospital_stays where discharged_at is null union select clinic_id from private.hospital_daily_orders d where not exists(select 1 from private.hospital_order_stops x where x.order_id=d.id) order by clinic_id loop
 -- Each clinic has its own transaction sub-block; errors are recorded, not silently dropped.
 begin perform private.hospital_automation_clinic(c);
 exception when others then
 insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(c,null,'hospital_automation_failed',c::text,jsonb_build_object('sqlstate',sqlstate));
 end;
 end loop;
 update private.hospital_automation_runtime set last_run_at=clock_timestamp();
end$$;
create function public.hospital_notice_route_set(p_clinic uuid,p_primary uuid,p_mvz uuid,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare fp jsonb;id uuid;a timestamptz;b timestamptz;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 perform private.hospital_order_permission(p_clinic,'hospital.automation.manage',null,false);
 select created_at into a from public.clinic_members where clinic_id=p_clinic and user_id=p_primary;
 select created_at into b from public.clinic_members where clinic_id=p_clinic and user_id=p_mvz;
 if p_primary is not distinct from p_mvz or not coalesce(private.hospital_notice_recipient(p_clinic,p_primary,a,false),false) or not coalesce(private.hospital_notice_recipient(p_clinic,p_mvz,b,true),false) then raise exception 'current_notice_recipients_required';end if;
 fp=jsonb_build_object('kind','hospital_notice_route','primary',p_primary,'mvz',p_mvz,'primary_since',a,'mvz_since',b);
 id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then return id;end if;
 insert into private.hospital_notice_routes(clinic_id,primary_user,mvz_user,primary_member_since,mvz_member_since,created_by) values(p_clinic,p_primary,p_mvz,a,b,auth.uid()) returning hospital_notice_routes.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,id);
 perform private.permission_event(p_clinic,'hospital_notice_route_set',id);
 return id;
end$$;
create function public.hospital_daily_order_create(p_clinic uuid,p_stay uuid,p_data jsonb,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare g uuid;rg uuid;id uuid;fp jsonb;instant timestamptz;prev private.hospital_daily_orders;v integer=1;begin
 perform private.medication_lock(p_clinic);
 rg=private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 g=private.hospital_order_permission(p_clinic,'hospital.schedule',null,true);
 if not(select enabled from private.hospital_automation_runtime) then raise exception 'hospital_scheduler_not_enabled';end if;
 if jsonb_typeof(p_data) is distinct from 'object' or exists(select 1 from jsonb_object_keys(p_data) k where k not in ('procedure_id','label','instructions','first_day','last_day','zone','minutes','escalation_minutes','confirmed','replaces_id','change_reason')) then raise exception 'daily_order_fields_only';end if;
 if p_data->'confirmed' is distinct from 'true'::jsonb then raise exception 'reviewed_daily_order_required';end if;
 if exists(select 1 from unnest(array['procedure_id','label','instructions','first_day','last_day','zone']) k where jsonb_typeof(p_data->k) is distinct from 'string') or jsonb_typeof(p_data->'escalation_minutes') is distinct from 'number' then raise exception 'invalid_daily_order';end if;
 if not exists(select 1 from private.procedure_types pt where pt.id=(p_data->>'procedure_id')::uuid and pt.clinic_id=p_clinic and pt.active) then raise exception 'active_procedure_required';end if;
 fp=jsonb_build_object('kind','hospital_daily_order','stay',p_stay,'data',p_data);
 id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then return id;end if;
 perform 1 from public.hospital_stays st where st.id=p_stay and st.clinic_id=p_clinic and st.discharged_at is null for update;
 if not found then raise exception 'stay_inactive';end if;
 for instant in select due from private.hospital_order_times(p_data) loop
 if instant<=clock_timestamp() then raise exception 'past_order_time';end if;
 end loop;
 if p_data ? 'replaces_id' then
 select * into prev from private.hospital_daily_orders d where d.id=(p_data->>'replaces_id')::uuid and d.clinic_id=p_clinic and d.stay_id=p_stay;
 if not found or exists(select 1 from private.hospital_order_stops where order_id=prev.id) then raise exception 'active_own_stay_order_required';end if;
 if jsonb_typeof(p_data->'change_reason') is distinct from 'string' then raise exception 'change_reason_required';end if;
 perform private.hospital_order_stop(prev.id,'replaced',p_data->>'change_reason',auth.uid());v=prev.version+1;
 elsif p_data ? 'change_reason' then raise exception 'change_reason_requires_previous_order';end if;
 insert into private.hospital_daily_orders(clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,label,instructions,first_day,last_day,zone,minutes,escalation_minutes,replaces_id,version)
 values(p_clinic,p_stay,(p_data->>'procedure_id')::uuid,auth.uid(),g,rg,btrim(p_data->>'label'),btrim(p_data->>'instructions'),(p_data->>'first_day')::date,(p_data->>'last_day')::date,p_data->>'zone',array(select x::text::int from jsonb_array_elements(p_data->'minutes') x order by x::text::int),(p_data->>'escalation_minutes')::int,(p_data->>'replaces_id')::uuid,v) returning hospital_daily_orders.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,id);
 perform private.permission_event(p_clinic,'hospital_daily_order_created',id,jsonb_build_object('version',v,'replaces_id',prev.id,'permission_grant_id',g));
 perform private.hospital_automation_clinic(p_clinic);
 return id;
end$$;
create function public.hospital_daily_order_stop(p_clinic uuid,p_order uuid,p_reason text,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare fp jsonb;receipt uuid;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 perform private.hospital_order_permission(p_clinic,'hospital.schedule',null,true);
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'stop_reason_required';end if;
 fp=jsonb_build_object('kind','hospital_daily_stop','order',p_order,'reason',p_reason);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);if receipt is not null then return receipt;end if;
 if not exists(select 1 from private.hospital_daily_orders where id=p_order and clinic_id=p_clinic) then raise exception 'order_not_found';end if;
 if exists(select 1 from private.hospital_order_stops where order_id=p_order) then raise exception 'order_already_stopped';end if;
 perform private.hospital_order_stop(p_order,'manual',p_reason,auth.uid());
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,p_order);return p_order;
end$$;
create function public.hospital_notice_ack(p_clinic uuid,p_notice uuid,p_note text,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare n private.hospital_notices;fp jsonb;receipt uuid;begin
 perform private.medication_lock(p_clinic);
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 perform private.hospital_order_permission(p_clinic,'hospital.report',null,false);
 select * into n from private.hospital_notices where id=p_notice and clinic_id=p_clinic and recipient_id=auth.uid();
 if not found or not private.hospital_notice_recipient(p_clinic,auth.uid(),n.member_since,n.stage='mvz') then raise exception 'own_notice_required';end if;
 if coalesce(length(btrim(p_note)),0) not between 1 and 1000 then raise exception 'response_note_required';end if;
 fp=jsonb_build_object('kind','hospital_notice_ack','notice',p_notice,'note',p_note);
 receipt=private.vet_receipt(p_clinic,p_operation,fp);if receipt is not null then return receipt;end if;
 insert into private.hospital_notice_responses(notice_id,clinic_id,actor_id,note) values(n.id,p_clinic,auth.uid(),btrim(p_note));
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,n.id);
 perform private.permission_event(p_clinic,'hospital_notice_acknowledged',n.id,jsonb_build_object('task_id',n.task_id,'stage',n.stage));
 return n.id;
end$$;
create function public.hospital_automation_workspace(p_clinic uuid,p_stay uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare manage boolean;schedule boolean;begin
 perform private.hospital_order_permission(p_clinic,'hospital.read',null,false);
 if p_stay is not null and not exists(select 1 from public.hospital_stays where id=p_stay and clinic_id=p_clinic) then raise exception 'stay_not_found';end if;
 manage=private.permission_effective(p_clinic,auth.uid(),'hospital.automation.manage') is not null;
 schedule=private.clinical_professional_at(p_clinic,auth.uid(),clock_timestamp()) and private.permission_effective(p_clinic,auth.uid(),'hospital.schedule') is not null;
 return jsonb_build_object('schema_version',1,'clinic_id',p_clinic,'actor_id',auth.uid(),'stay_id',p_stay,
 'runtime',(select jsonb_build_object('enabled',enabled,'last_run_at',last_run_at) from private.hospital_automation_runtime),
 'actions',jsonb_build_object('manage',manage,'create',schedule and p_stay is not null and (select enabled from private.hospital_automation_runtime) and exists(select 1 from public.hospital_stays where id=p_stay and discharged_at is null)),
 'route',(select jsonb_build_object('primary_user',primary_user,'mvz_user',mvz_user,'created_by',created_by,'created_at',created_at,'primary_current',private.hospital_notice_recipient(p_clinic,primary_user,primary_member_since,false),'mvz_current',private.hospital_notice_recipient(p_clinic,mvz_user,mvz_member_since,true)) from private.hospital_notice_routes where clinic_id=p_clinic order by created_at desc,id desc limit 1),
 'members',case when manage then (select coalesce(jsonb_agg(jsonb_build_object('id',m.user_id,'name',coalesce(nullif(pv.name,''),u.email,m.user_id::text),'primary_eligible',private.hospital_notice_recipient(p_clinic,m.user_id,m.created_at,false),'mvz_eligible',private.hospital_notice_recipient(p_clinic,m.user_id,m.created_at,true)) order by m.user_id),'[]') from public.clinic_members m join auth.users u on u.id=m.user_id left join public.professional_profiles p on p.clinic_id=m.clinic_id and p.user_id=m.user_id left join lateral (select name from private.professional_profile_versions where profile_id=p.id order by version desc limit 1) pv on true where m.clinic_id=p_clinic) else '[]'::jsonb end,
 'procedures',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name) order by name),'[]') from private.procedure_types where clinic_id=p_clinic and active),
 'orders',(select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('patient_name',p.name,'stop',to_jsonb(x),'can_stop',schedule and x.order_id is null) order by o.created_at desc,o.id),'[]') from private.hospital_daily_orders o join public.hospital_stays s on s.id=o.stay_id and s.clinic_id=o.clinic_id join public.vet_patients p on p.id=s.patient_id and p.clinic_id=o.clinic_id left join private.hospital_order_stops x on x.order_id=o.id where o.clinic_id=p_clinic and (p_stay is null or o.stay_id=p_stay)),
 'notices',(select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('stay_id',s.id,'response',to_jsonb(a),'patient_name',p.name,'task_label',t.label,'task_state',t.state,'due_at',t.due_at,'can_ack',n.recipient_id=auth.uid() and a.notice_id is null and private.hospital_notice_recipient(p_clinic,auth.uid(),n.member_since,n.stage='mvz')) order by n.created_at desc,n.id),'[]') from private.hospital_notices n join public.hospital_tasks t on t.id=n.task_id and t.clinic_id=n.clinic_id join public.hospital_stays s on s.id=t.stay_id and s.clinic_id=n.clinic_id join public.vet_patients p on p.id=s.patient_id and p.clinic_id=n.clinic_id left join private.hospital_notice_responses a on a.notice_id=n.id where n.clinic_id=p_clinic and (p_stay is null or s.id=p_stay)));
end$$;
alter function public.hospital_snapshot(uuid) set schema private;
alter function private.hospital_snapshot(uuid) rename to hospital_snapshot_before_automation;
revoke all on function private.hospital_snapshot_before_automation(uuid) from public,anon,authenticated,service_role;
create function public.hospital_snapshot(p_clinic_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare b jsonb;begin b=private.hospital_snapshot_before_automation(p_clinic_id);
 return b||jsonb_build_object('capabilities',(b->'capabilities')||jsonb_build_object('automation_version',1));end$$;
-- Private worker runs only as the scheduler owner. Never expose service credentials to phones.
do $$declare f record;begin
 for f in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='private' and p.proname in ('hospital_wall_time','hospital_order_times','hospital_notice_recipient','hospital_order_stop','hospital_automation_clinic','hospital_automation_tick') loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);end loop;
end$$;
revoke all on function public.hospital_snapshot(uuid),public.hospital_automation_workspace(uuid,uuid),public.hospital_notice_route_set(uuid,uuid,uuid,text),public.hospital_daily_order_create(uuid,uuid,jsonb,text),public.hospital_daily_order_stop(uuid,uuid,text,text),public.hospital_notice_ack(uuid,uuid,text,text) from public,anon,service_role;
grant execute on function public.hospital_snapshot(uuid),public.hospital_automation_workspace(uuid,uuid),public.hospital_notice_route_set(uuid,uuid,uuid,text),public.hospital_daily_order_create(uuid,uuid,jsonb,text),public.hospital_daily_order_stop(uuid,uuid,text,text),public.hospital_notice_ack(uuid,uuid,text,text) to authenticated;
select private.beta_install_guards();
notify pgrst,'reload schema';
commit;
