-- Operational synthetic dates; no clinical values.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
insert into auth.users(id,email,email_confirmed_at) values
('00000000-0000-0000-0000-000000009900','duty-admin@example.test',now()),
('00000000-0000-0000-0000-000000009901','duty-self@example.test',now()),
('00000000-0000-0000-0000-000000009902','duty-cover@example.test',now()),
('00000000-0000-0000-0000-000000009903','duty-other@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009900',false);
select public.create_clinic('Synthetic duty clinic') as clinic \gset
select set_config('test.clinic',:'clinic',false);
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000009901','auxiliar'),(:'clinic','00000000-0000-0000-0000-000000009902','auxiliar');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000009901','hospital.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000009901','hospital.report',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000009902','hospital.read',null,now()+interval '1 day','Synthetic');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000009902','hospital.report',null,now()+interval '1 day','Synthetic');
select set_config('test.duty',jsonb_build_object('kind','shift','start_day',current_date,'start_minute',0,'end_day',current_date+1,'end_minute',0,'zone','Etc/UTC','reason','Synthetic shift')::text,false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009901',false);
set role authenticated;
select public.team_duty_save(:'clinic',auth.uid(),current_setting('test.duty')::jsonb,repeat('d1',24)) as shift \gset
select set_config('test.shift',:'shift',false);
select pg_temp.assert_true(public.team_duty_save(:'clinic',auth.uid(),current_setting('test.duty')::jsonb,repeat('d1',24))=:'shift','idempotency');
select pg_temp.expect_error($q$select public.team_duty_save(current_setting('test.clinic')::uuid,auth.uid(),current_setting('test.duty')::jsonb||'{"reason":"different"}',repeat('d1',24))$q$,'operation_payload_changed');
select pg_temp.expect_error($q$select public.team_duty_save(current_setting('test.clinic')::uuid,auth.uid(),current_setting('test.duty')::jsonb,repeat('d2',24))$q$,'overlapping_schedule');
select pg_temp.expect_error($q$select public.team_duty_save(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000009902',current_setting('test.duty')::jsonb,repeat('d2',24))$q$,'schedule_authority_required');
select pg_temp.expect_error($q$select public.team_duty_save(current_setting('test.clinic')::uuid,auth.uid(),current_setting('test.duty')::jsonb||'{"kind":"absence"}',repeat('d2',24))$q$,'schedule_authority_required');
select pg_temp.expect_error('select * from private.team_duty_entries','permission denied');
select pg_temp.assert_true(jsonb_array_length(public.team_duty_workspace(:'clinic')->'members')=1,'self workspace exposes coworkers');
reset role;
select pg_temp.assert_true(private.team_on_duty(:'clinic','00000000-0000-0000-0000-000000009901',current_date),'start inclusive');
select pg_temp.assert_true(not private.team_on_duty(:'clinic','00000000-0000-0000-0000-000000009901',current_date+1),'end exclusive');
select pg_temp.assert_true(not private.team_on_duty(:'clinic','00000000-0000-0000-0000-000000009902',now()),'unscheduled cover on duty');
select pg_temp.assert_true((select count(*)=1 from private.hospital_duty_recipients(:'clinic','00000000-0000-0000-0000-000000009901',false)),'primary routing');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009900',false);
set role authenticated;
select public.team_duty_save(:'clinic','00000000-0000-0000-0000-000000009901',current_setting('test.duty')::jsonb||'{"kind":"absence","cover_id":"00000000-0000-0000-0000-000000009902","reason":"Synthetic authorized absence"}',repeat('d3',24)) as absence \gset
select set_config('test.absence',:'absence',false);
reset role;
select pg_temp.assert_true(not private.team_on_duty(:'clinic','00000000-0000-0000-0000-000000009901',now()),'absence must override shift');
select pg_temp.assert_true(private.team_on_duty(:'clinic','00000000-0000-0000-0000-000000009902',now()),'cover not on duty');
select pg_temp.assert_true((select array_agg(user_id)=array['00000000-0000-0000-0000-000000009902'::uuid] from private.hospital_duty_recipients(:'clinic','00000000-0000-0000-0000-000000009901',false)),'absent received or cover missed');
select pg_temp.assert_true((select count(*)=0 from private.hospital_duty_recipients(:'clinic','00000000-0000-0000-0000-000000009901',true)),'coverage granted MVZ authority');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009901',false);set role authenticated;
select pg_temp.expect_error($q$select public.team_duty_cancel(current_setting('test.clinic')::uuid,current_setting('test.absence')::uuid,'self override',repeat('d4',24))$q$,'schedule_authority_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009903',false);set role authenticated;
select pg_temp.expect_error($q$select public.team_duty_workspace(current_setting('test.clinic')::uuid)$q$,'membership_required');
select pg_temp.expect_error($q$select public.team_duty_save(current_setting('test.clinic')::uuid,auth.uid(),current_setting('test.duty')::jsonb,repeat('d4',24))$q$,'membership_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009900',false);set role authenticated;
select public.team_duty_save(:'clinic','00000000-0000-0000-0000-000000009902',current_setting('test.duty')::jsonb||'{"kind":"absence"}',repeat('d5',24)) as cover_absence \gset
reset role;
select pg_temp.assert_true(not private.team_on_duty(:'clinic','00000000-0000-0000-0000-000000009902',now()),'absent cover must be excluded');
select pg_temp.assert_true((select count(*)=0 from private.hospital_duty_recipients(:'clinic','00000000-0000-0000-0000-000000009901',false)),'no qualified duty must return empty');
set role authenticated;
select public.team_duty_cancel(:'clinic',:'absence','Synthetic cancellation',repeat('d6',24));
select public.team_duty_cancel(:'clinic',:'absence','Synthetic cancellation',repeat('d6',24));
select public.team_duty_save(:'clinic','00000000-0000-0000-0000-000000009901',current_setting('test.duty')::jsonb||jsonb_build_object('replaces_id',:'shift','reason','Admin correction'),repeat('d7',24)) as revised \gset
select pg_temp.expect_error($q$select public.team_duty_save(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000009901',current_setting('test.duty')::jsonb||jsonb_build_object('replaces_id',current_setting('test.shift')),repeat('d8',24))$q$,'stale_schedule');
reset role;
select pg_temp.assert_true(private.team_on_duty(:'clinic','00000000-0000-0000-0000-000000009901',now()),'cancellation did not restore shift');
select pg_temp.expect_error($q$update private.team_duty_entries set reason='rewrite' where id=current_setting('test.shift')::uuid$q$,'append_only_permission_record');

-- End-to-end worker routing: preserve historical notices but route new ones to current cover.
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values('00000000-0000-0000-0000-000000009910',:'clinic','Synthetic duty patient','synthetic','sin especificar','00000000-0000-0000-0000-000000009900');
insert into public.hospital_stays(id,clinic_id,patient_id,cage,admitted_by) values('00000000-0000-0000-0000-000000009910',:'clinic','00000000-0000-0000-0000-000000009910','Synthetic duty cage','00000000-0000-0000-0000-000000009900');
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by) values('00000000-0000-0000-0000-000000009910',:'clinic','00000000-0000-0000-0000-000000009910','revision','Synthetic duty notice','Synthetic only',clock_timestamp()-interval '5 minutes',1,'00000000-0000-0000-0000-000000009900');
insert into private.hospital_notice_routes(clinic_id,primary_user,mvz_user,primary_member_since,mvz_member_since,created_by)
select :'clinic',a.user_id,b.user_id,a.created_at,b.created_at,b.user_id from public.clinic_members a join public.clinic_members b on b.clinic_id=a.clinic_id where a.clinic_id=:'clinic' and a.user_id='00000000-0000-0000-0000-000000009901' and b.user_id='00000000-0000-0000-0000-000000009900';
select pg_temp.assert_true(not(select duty_routing_enabled from private.hospital_automation_runtime),'migration auto enabled routing');
update private.hospital_automation_runtime set enabled=true,duty_routing_enabled=true;
select private.hospital_automation_clinic(:'clinic');
select pg_temp.assert_true((select count(*)=1 from private.hospital_notices where clinic_id=:'clinic' and recipient_id='00000000-0000-0000-0000-000000009901'),'on duty worker primary missing');
set role authenticated;
select public.team_duty_cancel(:'clinic',:'cover_absence','Synthetic cover returns',repeat('e1',24));
select public.team_duty_save(:'clinic','00000000-0000-0000-0000-000000009901',current_setting('test.duty')::jsonb||'{"kind":"absence","cover_id":"00000000-0000-0000-0000-000000009902"}',repeat('e2',24));
reset role;
select private.hospital_automation_clinic(:'clinic');select private.hospital_automation_clinic(:'clinic');
select pg_temp.assert_true((select count(*)=1 from private.hospital_notices where clinic_id=:'clinic' and recipient_id='00000000-0000-0000-0000-000000009902'),'worker cover missing or duplicated');
select pg_temp.assert_true((select count(*)=0 from private.hospital_notices where clinic_id=:'clinic' and stage='mvz'),'worker assigned unqualified MVZ');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009902',false);set role authenticated;
select pg_temp.assert_true((public.hospital_snapshot(:'clinic')->'capabilities'->>'duty_routing_version')='1','missing device cancellation capability');
select pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.team_duty_workspace(:'clinic')->'entries') e where e->>'cover_id'=auth.uid()::text and e->>'reason'='Cobertura asignada por administración' and e->>'can_edit'='false'),'cover schedule unavailable or reason exposed');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009900',false);
update private.hospital_automation_runtime set duty_routing_enabled=false;
delete from public.clinic_members where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000009901';
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000009901','auxiliar');
select pg_temp.assert_true(not private.team_on_duty(:'clinic','00000000-0000-0000-0000-000000009901',now()),'rejoin revived old shifts');
select pg_temp.assert_true(not(select duty_routing_enabled from private.hospital_automation_runtime),'migration auto enabled routing');
