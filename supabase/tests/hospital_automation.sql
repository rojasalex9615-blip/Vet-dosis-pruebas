-- Synthetic operational schedules only. No clinical protocol or notification provider.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('test.clinic',:'clinic',false);
select pg_temp.assert_true(not (select enabled from private.hospital_automation_runtime),'scheduler silently activated');
select private.hospital_automation_tick();
select pg_temp.assert_true((select last_run_at is null from private.hospital_automation_runtime),'disabled worker ran');
select pg_temp.assert_true(private.hospital_wall_time('2026-10-25',600,'Asia/Kolkata')='2026-10-25T04:30:00Z','fractional offset lost');
select pg_temp.expect_error($q$select private.hospital_wall_time('2026-11-01',90,'America/New_York')$q$,'ambiguous_or_missing_hospital_time');
select pg_temp.expect_error($q$select private.hospital_wall_time('2027-03-14',150,'America/New_York')$q$,'ambiguous_or_missing_hospital_time');
select pg_temp.expect_error($q$select private.hospital_wall_time('2026-10-25',10,'Synthetic/Invalid')$q$,'invalid_hospital_zone_or_time');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_procedure_set(:'clinic',null,'Synthetic daily order',true) as procedure \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','procedure.perform',:'procedure',clock_timestamp()+interval '1 day','Synthetic daily order');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','hospital.automation.manage',null,clock_timestamp()+interval '1 day','Synthetic route configuration');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','hospital.report',null,clock_timestamp()+interval '1 day','Synthetic acknowledgement');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000160','hospital.report',null,clock_timestamp()+interval '1 day','Synthetic acknowledgement');
reset role;
insert into private.clinic_responsible_designations(clinic_id,user_id,member_since,proposed_by,valid_until,accepted_at)
select clinic_id,user_id,created_at,'00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 day',clock_timestamp() from public.clinic_members where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000151';
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values('00000000-0000-0000-0000-000000000800',:'clinic','Synthetic automation patient','synthetic','sin especificar','00000000-0000-0000-0000-000000000150');
insert into public.hospital_stays(id,clinic_id,patient_id,cage,admitted_by,admitted_at) values('00000000-0000-0000-0000-000000000800',:'clinic','00000000-0000-0000-0000-000000000800','Synthetic daily area','00000000-0000-0000-0000-000000000151',clock_timestamp()-interval '1 day');
select set_config('test.order',jsonb_build_object('procedure_id',:'procedure','label','Synthetic daily care','instructions','Synthetic entered indication','first_day',to_char(current_date+1,'YYYY-MM-DD'),'last_day',to_char(current_date+3,'YYYY-MM-DD'),'zone','Etc/UTC','minutes',jsonb_build_array(600,1080),'escalation_minutes',1,'confirmed',true)::text,false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.assert_true((public.hospital_snapshot(:'clinic')->'capabilities'->>'automation_version')::int=1,'capability missing');
select pg_temp.expect_error($q$select public.hospital_daily_order_create(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb,repeat('81',24))$q$,'hospital_scheduler_not_enabled');
select public.hospital_notice_route_set(:'clinic','00000000-0000-0000-0000-000000000160','00000000-0000-0000-0000-000000000151',repeat('80',24));
select pg_temp.expect_error($q$select public.hospital_notice_route_set(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000151','00000000-0000-0000-0000-000000000151',repeat('82',24))$q$,'current_notice_recipients_required');
select pg_temp.expect_error('select private.hospital_automation_tick()','permission denied');
select pg_temp.expect_error('select * from private.hospital_daily_orders','permission denied');
reset role;
update private.hospital_automation_runtime set enabled=true;
set role authenticated;
select public.hospital_daily_order_create(:'clinic','00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb,repeat('81',24)) as original \gset
select set_config('test.original',:'original',false);
select pg_temp.assert_true(public.hospital_daily_order_create(:'clinic','00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb,repeat('81',24))=:'original','retry duplicated order');
select pg_temp.expect_error($q$select public.hospital_daily_order_create(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb||'{"label":"changed"}',repeat('81',24))$q$,'operation_payload_changed');
select pg_temp.expect_error($q$select public.hospital_daily_order_create(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb||'{"minutes":[600,600]}',repeat('82',24))$q$,'invalid_daily_times');
select pg_temp.expect_error($q$select public.hospital_daily_order_create(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb||'{"confirmed":false}',repeat('82',24))$q$,'reviewed_daily_order_required');
select pg_temp.expect_error($q$select public.hospital_daily_order_create(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb||'{"author_id":"forged"}',repeat('82',24))$q$,'daily_order_fields_only');
reset role;
select pg_temp.assert_true((select count(*)=2 from public.hospital_tasks where daily_order_id=:'original'),'worker did not generate tomorrow only');
select private.hospital_automation_tick();select private.hospital_automation_tick();
select pg_temp.assert_true((select count(*)=2 from public.hospital_tasks where daily_order_id=:'original'),'tick duplicated tasks');
select pg_temp.assert_true((select bool_and(kind='revision' and state='pending' and medication_record_id is null) from public.hospital_tasks where daily_order_id=:'original'),'generated medication or confirmation');
select pg_temp.assert_true(private.rx_vial_balance('00000000-0000-0000-0000-000000000410')=8,'worker moved medication');
-- Worker recovers missed dates from a persisted previously authorized order after downtime.
insert into private.hospital_daily_orders(id,clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,label,instructions,first_day,last_day,zone,minutes,escalation_minutes,created_at,version)
select '00000000-0000-0000-0000-000000000810',clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,'Synthetic catch-up','Synthetic entered indication',current_date-1,current_date+1,'Etc/UTC',array[0],1,clock_timestamp()-interval '3 days',1 from private.hospital_daily_orders where id=:'original';
select private.hospital_automation_tick();
select pg_temp.assert_true((select count(*)=3 from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000810'),'downtime lost due dates');
select id as due_task from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000810' and due_at<clock_timestamp() order by due_at limit 1 \gset
select id as primary_notice from private.hospital_notices where task_id=:'due_task' and stage='primary' \gset
select id as mvz_notice from private.hospital_notices where task_id=:'due_task' and stage='mvz' \gset
select set_config('test.notice',:'primary_notice',false);
select pg_temp.assert_true(:'mvz_notice' is not null,'no escalation for unacknowledged task');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select public.hospital_notice_ack(:'clinic',:'primary_notice','Synthetic received',repeat('83',24));
select public.hospital_notice_ack(:'clinic',:'primary_notice','Synthetic received',repeat('83',24));
select pg_temp.expect_error($q$select public.hospital_notice_ack(current_setting('test.clinic')::uuid,current_setting('test.notice')::uuid,'changed',repeat('83',24))$q$,'operation_payload_changed');
reset role;
select pg_temp.assert_true((select state='pending' and performed_by is null from public.hospital_tasks where id=:'due_task'),'ack confirmed care');
select pg_temp.assert_true((select count(*)=1 from private.hospital_notice_responses where notice_id=:'primary_notice'),'ack duplicated');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_notice_ack(current_setting('test.clinic')::uuid,current_setting('test.notice')::uuid,'Synthetic wrong person',repeat('84',24))$q$,'own_notice_required');
select public.hospital_daily_order_create(:'clinic','00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb||jsonb_build_object('replaces_id',:'original','change_reason','Synthetic new indication'),repeat('85',24)) as revised \gset
reset role;
select pg_temp.assert_true((select version=2 and replaces_id=:'original' from private.hospital_daily_orders where id=:'revised'),'version lineage lost');
select pg_temp.assert_true(not exists(select 1 from public.hospital_tasks where daily_order_id=:'original' and state='pending'),'old future tasks not cancelled');
select pg_temp.expect_error('update private.hospital_daily_orders set label=''changed''','append_only_permission_record');
set role authenticated;
select public.hospital_daily_order_stop(:'clinic',:'revised','Synthetic stop',repeat('86',24));
select public.hospital_daily_order_stop(:'clinic',:'revised','Synthetic stop',repeat('86',24));
select pg_temp.assert_true(jsonb_array_length(public.hospital_automation_workspace(:'clinic','00000000-0000-0000-0000-000000000800')->'orders')=3,'workspace history lost');
reset role;
-- An acknowledgement before the threshold suppresses escalation, without completing care.
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,procedure_type_id,authority_grant_id)
select '00000000-0000-0000-0000-000000000830',clinic_id,stay_id,'revision','Synthetic before escalation','Synthetic',clock_timestamp()-interval '1 minute',120,author_id,procedure_id,schedule_grant from private.hospital_daily_orders where id=:'original';
select private.hospital_automation_tick();
select id as early_notice from private.hospital_notices where task_id='00000000-0000-0000-0000-000000000830' and stage='primary' \gset
select pg_temp.assert_true(not exists(select 1 from private.hospital_notices where task_id='00000000-0000-0000-0000-000000000830' and stage='mvz'),'escalated before threshold');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select public.hospital_notice_ack(:'clinic',:'early_notice','Synthetic early response',repeat('87',24));
reset role;
update public.hospital_tasks set due_at=clock_timestamp()-interval '3 hours' where id='00000000-0000-0000-0000-000000000830';
select private.hospital_automation_tick();
select pg_temp.assert_true(not exists(select 1 from private.hospital_notices where task_id='00000000-0000-0000-0000-000000000830' and stage='mvz'),'ack failed to suppress escalation');
-- Removing the primary recipient does not prevent a current responsible MVZ receiving escalation.
select id as primary_grant from private.member_permission_grants where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000160' and code='hospital.report' and not exists(select 1 from private.permission_revocations r where r.grant_id=member_permission_grants.id) order by granted_at desc limit 1 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'primary_grant','Synthetic revoked responder');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_notice_ack(current_setting('test.clinic')::uuid,current_setting('test.notice')::uuid,'Synthetic received',repeat('83',24))$q$,'explicit_permission_required');
reset role;
-- Original author grant revocation halts recurrence and future tasks; due tasks survive.
select schedule_grant as original_grant from private.hospital_daily_orders where id=:'original' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'original_grant','Synthetic author revocation');
reset role;select set_config('request.jwt.claim.sub','',false);
select private.hospital_automation_tick();
select pg_temp.assert_true(exists(select 1 from private.hospital_order_stops where order_id='00000000-0000-0000-0000-000000000810' and kind='authority_lost' and actor_id is null),'revoked author kept generating');
select pg_temp.assert_true(exists(select 1 from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000810' and due_at<clock_timestamp() and state='pending'),'revocation silently erased due care');
select pg_temp.assert_true(not exists(select 1 from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000810' and due_at>clock_timestamp() and state='pending'),'revoked future care not stopped');
-- Regranting never resumes stopped orders.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','hospital.schedule',null,clock_timestamp()+interval '1 day','Synthetic new authority');
reset role;select private.hospital_automation_tick();
select pg_temp.assert_true((select count(*)=3 from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000810'),'stopped order resumed after regrant');
-- Discharge preserves original resolution contract and excludes future generation.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.hospital_daily_order_create(:'clinic','00000000-0000-0000-0000-000000000800',current_setting('test.order')::jsonb,repeat('88',24)) as discharge_order \gset
select public.hospital_discharge_preview(:'clinic','00000000-0000-0000-0000-000000000800') as preview \gset
select public.hospital_discharge_confirm(:'clinic','00000000-0000-0000-0000-000000000800',(:'preview'::jsonb->>'version')::int,:'preview'::jsonb->>'pending_hash','Synthetic daily discharge',repeat('89',24));
reset role;select set_config('request.jwt.claim.sub','',false);select private.hospital_automation_tick();
select pg_temp.assert_true(not exists(select 1 from public.hospital_tasks where stay_id='00000000-0000-0000-0000-000000000800' and state='pending'),'discharge kept pending tasks');
-- The tick scans only active stays; a discharged order remains historical but cannot generate.
select private.hospital_automation_clinic(:'clinic');
select pg_temp.assert_true(exists(select 1 from private.hospital_order_stops where order_id=:'discharge_order' and kind='discharged'),'discharge stop history missing');
select pg_temp.assert_true(not exists(select 1 from public.audit_log where action='hospital_automation_failed'),'worker silently failed');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_automation_workspace(current_setting('test.clinic')::uuid,null)$q$,'explicit_permission_required');
reset role;set role anon;
select pg_temp.expect_error('select public.hospital_automation_workspace(null,null)','permission denied');
reset role;
select pg_temp.assert_true(not(select migration_reviewed or enforcement_enabled from private.permission_policy),'permissions activated');
