-- Local candidate; install after 14G. No automatic remote activation.
begin;
alter table private.hospital_automation_runtime add column duty_routing_enabled boolean not null default false;
create table private.team_duty_entries(
 id uuid primary key default gen_random_uuid(), clinic_id uuid not null references public.clinics(id),
 user_id uuid not null references auth.users(id), member_since timestamptz not null,
 kind text not null check(kind in ('shift','absence')), starts_at timestamptz not null, ends_at timestamptz not null,
 zone text not null, reason text not null check(length(reason) between 1 and 1000),
 cover_id uuid references auth.users(id), cover_since timestamptz,
 created_by uuid not null references auth.users(id), created_at timestamptz not null default clock_timestamp(),
 check(ends_at>starts_at), check((cover_id is null)=(cover_since is null)),
 check(cover_id is null or (kind='absence' and cover_id<>user_id))
);
create table private.team_duty_cancellations(
 entry_id uuid primary key references private.team_duty_entries(id),
 actor_id uuid not null references auth.users(id), reason text not null check(length(reason) between 1 and 1000),
 created_at timestamptz not null default clock_timestamp()
);
alter table private.team_duty_entries enable row level security;
alter table private.team_duty_cancellations enable row level security;
revoke all on private.team_duty_entries,private.team_duty_cancellations from public,anon,authenticated,service_role;
create trigger immutable before update or delete on private.team_duty_entries for each row execute function private.permission_immutable();
create trigger immutable before update or delete on private.team_duty_cancellations for each row execute function private.permission_immutable();
create index team_duty_lookup on private.team_duty_entries(clinic_id,user_id,starts_at,ends_at);
create function private.team_on_duty(c uuid,u uuid,at_time timestamptz) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.clinic_members m where m.clinic_id=c and m.user_id=u
 and not exists(select 1 from private.team_duty_entries a where a.clinic_id=c and a.user_id=u and a.member_since=m.created_at and a.kind='absence' and a.starts_at<=at_time and at_time<a.ends_at and not exists(select 1 from private.team_duty_cancellations x where x.entry_id=a.id))
 and exists(select 1 from private.team_duty_entries e where e.clinic_id=c and e.starts_at<=at_time and at_time<e.ends_at
 and not exists(select 1 from private.team_duty_cancellations x where x.entry_id=e.id)
 and ((e.kind='shift' and e.user_id=u and e.member_since=m.created_at)
 or (e.kind='absence' and e.cover_id=u and e.cover_since=m.created_at and exists(select 1 from public.clinic_members absent where absent.clinic_id=c and absent.user_id=e.user_id and absent.created_at=e.member_since)))));
$$;
create function public.team_duty_save(p_clinic uuid,p_user uuid,p_data jsonb,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
<<duty>>
declare admin boolean;since timestamptz;cover_since timestamptz;cover uuid;kind text;a timestamptz;b timestamptz;old private.team_duty_entries;id uuid;fp jsonb;begin
 perform private.medication_lock(p_clinic);
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'membership_required';end if;
 admin=private.has_clinic_role(p_clinic,array['admin']::text[]);
 kind=p_data->>'kind';
 if kind is null or kind not in ('shift','absence') or (not admin and (p_user<>auth.uid() or kind='absence')) then raise exception 'schedule_authority_required';end if;
 if exists(select 1 from jsonb_object_keys(p_data) k where k not in ('kind','start_day','start_minute','end_day','end_minute','zone','reason','cover_id','replaces_id')) then raise exception 'schedule_fields_only';end if;
 select created_at into since from public.clinic_members where clinic_id=p_clinic and user_id=p_user;
 if since is null then raise exception 'current_member_required';end if;
 fp=jsonb_build_object('kind','team_duty_save','user',p_user,'since',since,'data',p_data);
 id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then return id;end if;
 a=private.hospital_wall_time((p_data->>'start_day')::date,(p_data->>'start_minute')::int,p_data->>'zone');
 b=private.hospital_wall_time((p_data->>'end_day')::date,(p_data->>'end_minute')::int,p_data->>'zone');
 if a is null or b is null or b<=a or b<=clock_timestamp() or b-a>(case when kind='shift' then interval '24 hours' else interval '90 days' end) or a>clock_timestamp()+interval '366 days' or coalesce(length(btrim(p_data->>'reason')),0) not between 1 and 1000 then raise exception 'invalid_schedule_interval_or_reason';end if;
 cover=nullif(p_data->>'cover_id','')::uuid;
 if cover is not null then
 select created_at into cover_since from public.clinic_members where clinic_id=p_clinic and user_id=cover;
 if kind<>'absence' or cover=p_user or cover_since is null then raise exception 'invalid_cover';end if;
 end if;
 if p_data->>'replaces_id' is not null then
 select * into old from private.team_duty_entries where team_duty_entries.id=(p_data->>'replaces_id')::uuid and clinic_id=p_clinic and user_id=p_user and member_since=since;
 if not found or old.kind<>kind or old.ends_at<=clock_timestamp() or exists(select 1 from private.team_duty_cancellations where entry_id=old.id) then raise exception 'stale_schedule';end if;
 insert into private.team_duty_cancellations(entry_id,actor_id,reason) values(old.id,auth.uid(),btrim(p_data->>'reason'));
 end if;
 if exists(select 1 from private.team_duty_entries e where e.clinic_id=p_clinic and e.user_id=p_user and e.member_since=since and e.kind=duty.kind and e.starts_at<b and a<e.ends_at and not exists(select 1 from private.team_duty_cancellations x where x.entry_id=e.id)) then raise exception 'overlapping_schedule';end if;
 insert into private.team_duty_entries(clinic_id,user_id,member_since,kind,starts_at,ends_at,zone,reason,cover_id,cover_since,created_by)
 values(p_clinic,p_user,since,kind,a,b,p_data->>'zone',btrim(p_data->>'reason'),cover,cover_since,auth.uid()) returning team_duty_entries.id into id;
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,id);
 -- Absence reasons stay private; generic audit never copies health/personal details.
 perform private.permission_event(p_clinic,'team_duty_saved',id,jsonb_build_object('kind',kind,'replaces_id',old.id));
 return id;
end$$;
create function public.team_duty_cancel(p_clinic uuid,p_entry uuid,p_reason text,p_operation text) returns uuid
language plpgsql security definer set search_path='' as $$
declare e private.team_duty_entries;fp jsonb;id uuid;begin
 perform private.medication_lock(p_clinic);
 select * into e from private.team_duty_entries where clinic_id=p_clinic and team_duty_entries.id=p_entry;
 if not found or not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) or not (private.has_clinic_role(p_clinic,array['admin']::text[]) or (e.user_id=auth.uid() and e.kind='shift' and exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=e.user_id and created_at=e.member_since))) then raise exception 'schedule_authority_required';end if;
 if coalesce(length(btrim(p_reason)),0) not between 1 and 1000 then raise exception 'reason_required';end if;
 fp=jsonb_build_object('kind','team_duty_cancel','entry',p_entry,'reason',p_reason);
 id=private.vet_receipt(p_clinic,p_operation,fp);if id is not null then return id;end if;
 if e.ends_at<=clock_timestamp() or exists(select 1 from private.team_duty_cancellations where entry_id=e.id) then raise exception 'stale_schedule';end if;
 insert into private.team_duty_cancellations values(e.id,auth.uid(),btrim(p_reason),clock_timestamp());
 insert into private.vet_operation_receipts values(auth.uid(),p_clinic,p_operation,fp,e.id);
 perform private.permission_event(p_clinic,'team_duty_cancelled',e.id);return e.id;
end$$;
create function public.team_duty_workspace(p_clinic uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare admin boolean;begin
 if not exists(select 1 from public.clinic_members where clinic_id=p_clinic and user_id=auth.uid()) then raise exception 'membership_required';end if;
 admin=private.has_clinic_role(p_clinic,array['admin']::text[]);
 return jsonb_build_object('version',1,'clinic_id',p_clinic,'actor_id',auth.uid(),'admin',admin,
 'qualified_primary_on_duty',case when admin then (select count(*) from private.hospital_duty_recipients(p_clinic,null,false)) else null end,
 'qualified_mvz_on_duty',case when admin then (select count(*) from private.hospital_duty_recipients(p_clinic,null,true)) else null end,
 'members',(select coalesce(jsonb_agg(jsonb_build_object('id',m.user_id,'name',coalesce(u.email,m.user_id::text),'on_duty',private.team_on_duty(p_clinic,m.user_id,clock_timestamp())) order by m.user_id),'[]') from public.clinic_members m join auth.users u on u.id=m.user_id where m.clinic_id=p_clinic and (admin or m.user_id=auth.uid())),
 'entries',(select coalesce(jsonb_agg((to_jsonb(e)-'member_since'-'cover_since'-'reason')||jsonb_build_object('reason',case when admin or e.user_id=auth.uid() then e.reason else 'Cobertura asignada por administración' end,'cancelled',x.entry_id is not null,'cancel_reason',case when admin or e.user_id=auth.uid() then x.reason else null end,'cancelled_at',x.created_at,'cancelled_by',x.actor_id,'can_edit',x.entry_id is null and e.ends_at>clock_timestamp() and (admin or e.kind='shift')) order by e.starts_at desc),'[]') from private.team_duty_entries e left join private.team_duty_cancellations x on x.entry_id=e.id where e.clinic_id=p_clinic and (admin or e.user_id=auth.uid() or (e.cover_id=auth.uid() and exists(select 1 from public.clinic_members cm where cm.clinic_id=p_clinic and cm.user_id=auth.uid() and cm.created_at=e.cover_since))) and exists(select 1 from public.clinic_members m where m.clinic_id=p_clinic and m.user_id=e.user_id and m.created_at=e.member_since)));
end$$;
-- Keep eligibility separate: configuring a future route does not require today's shift.
create function private.hospital_duty_recipients(c uuid,preferred uuid,mvz boolean) returns table(user_id uuid,member_since timestamptz)
language sql stable security definer set search_path='' as $$
 with eligible as (select m.user_id,m.created_at from public.clinic_members m where m.clinic_id=c and private.team_on_duty(c,m.user_id,clock_timestamp()) and private.hospital_notice_recipient(c,m.user_id,m.created_at,mvz)),
 chosen as (select e.* from eligible e where e.user_id=preferred or exists(select 1 from private.team_duty_entries a where a.clinic_id=c and a.user_id=preferred and a.kind='absence' and a.cover_id=e.user_id and a.cover_since=e.created_at and a.starts_at<=clock_timestamp() and clock_timestamp()<a.ends_at and not exists(select 1 from private.team_duty_cancellations x where x.entry_id=a.id) and exists(select 1 from public.clinic_members m where m.clinic_id=c and m.user_id=a.user_id and m.created_at=a.member_since)))
 select * from chosen union all select * from eligible where not exists(select 1 from chosen);
$$;
alter function private.hospital_automation_clinic(uuid) rename to hospital_automation_clinic_before_duty;
revoke all on function private.hospital_automation_clinic_before_duty(uuid) from public,anon,authenticated,service_role;
create function private.hospital_automation_clinic(p_clinic uuid) returns void
language plpgsql security definer set search_path='' as $$
declare o private.hospital_daily_orders;s public.hospital_stays;r private.hospital_notice_routes;t public.hospital_tasks;instant timestamptz;task uuid;g uuid;cutoff date;begin
 if not(select duty_routing_enabled from private.hospital_automation_runtime) then perform private.hospital_automation_clinic_before_duty(p_clinic);return;end if;
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
 insert into private.hospital_notices(clinic_id,task_id,route_id,stage,recipient_id,member_since)
 select p_clinic,t.id,r.id,'primary',d.user_id,d.member_since from private.hospital_duty_recipients(p_clinic,r.primary_user,false) d
 where not exists(select 1 from private.hospital_notice_responses a join private.hospital_notices n on n.id=a.notice_id where n.task_id=t.id)
 on conflict(task_id,stage,recipient_id,member_since) do nothing;
 if t.due_at+make_interval(mins=>t.escalation_minutes)<=clock_timestamp()
 and not exists(select 1 from private.hospital_notice_responses a join private.hospital_notices n on n.id=a.notice_id where n.task_id=t.id) then
 insert into private.hospital_notices(clinic_id,task_id,route_id,stage,recipient_id,member_since)
 select p_clinic,t.id,r.id,'mvz',d.user_id,d.member_since from private.hospital_duty_recipients(p_clinic,r.mvz_user,true) d
 on conflict(task_id,stage,recipient_id,member_since) do nothing;
 end if;
 end loop;
end$$;
-- Schedule edits on the server cannot revoke a previously scheduled offline OS alarm.
-- Under duty routing use server delivery only; clients cancel their legacy alarm plan.
alter function public.hospital_snapshot(uuid) rename to hospital_snapshot_before_duty;
revoke all on function public.hospital_snapshot_before_duty(uuid) from public,anon,authenticated,service_role;
create function public.hospital_snapshot(p_clinic_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 result=public.hospital_snapshot_before_duty(p_clinic_id);
 if not(select duty_routing_enabled from private.hospital_automation_runtime) then return result;end if;
 return jsonb_set(result,'{capabilities}',coalesce(result->'capabilities','{}')||jsonb_build_object('duty_routing_version',1));
end$$;
do $$declare f record;begin
 for f in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname='private' and p.proname in ('team_on_duty','hospital_duty_recipients','hospital_automation_clinic')) or (n.nspname='public' and p.proname in ('team_duty_save','team_duty_cancel','team_duty_workspace','hospital_snapshot')) loop
 execute format('revoke all on function %s from public,anon,authenticated,service_role',f.signature);
 end loop;
end$$;
grant execute on function public.team_duty_save(uuid,uuid,jsonb,text),public.team_duty_cancel(uuid,uuid,text,text),public.team_duty_workspace(uuid),public.hospital_snapshot(uuid) to authenticated;
commit;
