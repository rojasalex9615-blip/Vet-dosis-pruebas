-- Synthetic care records; no clinical protocols or normal findings supplied.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('test.clinic',:'clinic',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);
set role authenticated;
select public.permission_procedure_set(:'clinic',null,'Synthetic structured care',true) as procedure \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','procedure.perform',:'procedure',clock_timestamp()+interval '1 day','Synthetic care result') as grant_id \gset
reset role;
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values('00000000-0000-0000-0000-000000000700',:'clinic','Synthetic care patient','synthetic','sin especificar','00000000-0000-0000-0000-000000000150');
insert into public.hospital_stays(id,clinic_id,patient_id,cage,admitted_by,admitted_at) values('00000000-0000-0000-0000-000000000700',:'clinic','00000000-0000-0000-0000-000000000700','Synthetic care area','00000000-0000-0000-0000-000000000151',clock_timestamp()-interval '1 hour');
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,procedure_type_id,authority_grant_id)
select x.id,:'clinic','00000000-0000-0000-0000-000000000700',case when x.n=707 then 'medicacion' else 'revision' end,'Synthetic care '||x.n,'Synthetic manually entered instruction',case when x.n=704 then clock_timestamp()+interval '1 day' else clock_timestamp()-interval '5 minutes' end,15,'00000000-0000-0000-0000-000000000151',case when x.n=703 then null else :'procedure'::uuid end,case when x.n=703 then null else g.id end
from private.member_permission_grants g cross join (select ('00000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid as id,n from generate_series(700,708) n) x where g.clinic_id=:'clinic' and g.user_id='00000000-0000-0000-0000-000000000151' and g.code='hospital.schedule';
update public.hospital_tasks set snoozed_until=clock_timestamp()+interval '10 minutes' where id='00000000-0000-0000-0000-000000000705';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);
set role authenticated;
select set_config('test.data',jsonb_build_object('care_kind','feeding','offered','2.123456789','consumed','0','unit','porción','findings','Synthetic observed text','observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'confirmed',true)::text,false);
select pg_temp.assert_true((public.hospital_snapshot(:'clinic')->'capabilities'->>'care_results_version')::int=1,'capability missing');
select pg_temp.assert_true((public.hospital_care_workspace(:'clinic','00000000-0000-0000-0000-000000000700')->'actions'->>'record')::boolean,'explicit professional denied');
select public.hospital_care_record(:'clinic','00000000-0000-0000-0000-000000000700',1,current_setting('test.data')::jsonb,repeat('71',24)) as first_result \gset
select pg_temp.assert_true(public.hospital_care_record(:'clinic','00000000-0000-0000-0000-000000000700',1,current_setting('test.data')::jsonb,repeat('71',24))=:'first_result','retry duplicated result');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000700',1,current_setting('test.data')::jsonb||'{"findings":"changed"}',repeat('71',24))$q$,'operation_payload_changed');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000701',2,current_setting('test.data')::jsonb,repeat('72',24))$q$,'task_version_conflict');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000701',1,current_setting('test.data')::jsonb||'{"consumed":"3"}',repeat('72',24))$q$,'violates check constraint');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000701',1,current_setting('test.data')::jsonb||'{"offered":"2e2"}',repeat('72',24))$q$,'exact_care_quantity_required');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000701',1,current_setting('test.data')::jsonb||'{"confirmed":false}',repeat('72',24))$q$,'care_confirmation_required');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000701',1,current_setting('test.data')::jsonb||'{"actor_id":"forged"}',repeat('72',24))$q$,'care_result_fields_only');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000703',1,current_setting('test.data')::jsonb,repeat('72',24))$q$,'typed_review_required');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000707',1,current_setting('test.data')::jsonb,repeat('72',24))$q$,'typed_review_required');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000704',1,current_setting('test.data')::jsonb,repeat('72',24))$q$,'invalid_care_observation_time');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000705',1,current_setting('test.data')::jsonb,repeat('72',24))$q$,'invalid_care_observation_time');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000701',1,current_setting('test.data')::jsonb||jsonb_build_object('observed_at',to_char(clock_timestamp()-interval '1 minute','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('72',24))$q$,'care_observation_authority_required');
reset role;
select pg_temp.assert_true((select state='pending' and version=1 from public.hospital_tasks where id='00000000-0000-0000-0000-000000000701'),'invalid result partially confirmed task');
select pg_temp.assert_true((select state='done' and version=2 and performed_by='00000000-0000-0000-0000-000000000151' and medication_record_id is null from public.hospital_tasks where id='00000000-0000-0000-0000-000000000700'),'result did not atomically confirm own review');
select pg_temp.assert_true(private.rx_vial_balance('00000000-0000-0000-0000-000000000410')=8,'care result changed medication volume');
select pg_temp.assert_true((select offered=2.123456789 and consumed=0 and actor_id='00000000-0000-0000-0000-000000000151' from private.hospital_care_results where id=:'first_result'),'exact amounts/own actor lost');
select pg_temp.expect_error('update private.hospital_care_results set findings=''changed''','append_only_permission_record');
set role authenticated;
select set_config('test.correction',(current_setting('test.data')::jsonb||jsonb_build_object('replaces_id',:'first_result','correction_reason','Synthetic correction','consumed','0.000000001'))::text,false);
select public.hospital_care_record(:'clinic','00000000-0000-0000-0000-000000000700',2,current_setting('test.correction')::jsonb,repeat('73',24)) as corrected \gset
select pg_temp.assert_true(public.hospital_care_record(:'clinic','00000000-0000-0000-0000-000000000700',2,current_setting('test.correction')::jsonb,repeat('73',24))=:'corrected','correction retry duplicated');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000700',2,current_setting('test.correction')::jsonb,repeat('74',24))$q$,'care_result_already_corrected');
select pg_temp.assert_true(jsonb_array_length(public.hospital_care_workspace(:'clinic','00000000-0000-0000-0000-000000000700')->'records')=2,'history lost');
-- Existing generic confirmation remains valid; only that performer can append its result.
select set_config('test.device',(current_setting('test.data')::jsonb-'offered'-'consumed'-'unit'||jsonb_build_object('care_kind','catheter_review','observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))::text,false);
select public.hospital_task_action(:'clinic','00000000-0000-0000-0000-000000000708',1,'perform');
select public.hospital_care_record(:'clinic','00000000-0000-0000-0000-000000000708',2,current_setting('test.device')::jsonb,repeat('75',24));
reset role;
select pg_temp.assert_true((select version=2 from public.hospital_tasks where id='00000000-0000-0000-0000-000000000708'),'append reconfirmed existing task');
select pg_temp.assert_true(exists(select 1 from public.audit_log where entity_id=:'first_result' and details->>'permission_grant_id'=:'grant_id'),'permission audit lost');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000161',false);
set role authenticated;
select pg_temp.assert_true(not (public.hospital_care_workspace(:'clinic','00000000-0000-0000-0000-000000000700')->'actions'->>'correct')::boolean,'reader got correction permission');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000702',1,current_setting('test.data')::jsonb,repeat('76',24))$q$,'explicit_permission_required');
select pg_temp.expect_error('select * from private.hospital_care_results','permission denied');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_care_workspace(current_setting('test.clinic')::uuid,null)$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000702',1,current_setting('test.data')::jsonb,repeat('76',24))$q$,'explicit_permission_required');
reset role;
-- History remains available after discharge; cancelled pending tasks cannot be performed.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.hospital_discharge_preview(:'clinic','00000000-0000-0000-0000-000000000700') as preview \gset
select public.hospital_discharge_confirm(:'clinic','00000000-0000-0000-0000-000000000700',(:'preview'::jsonb->>'version')::int,:'preview'::jsonb->>'pending_hash','Synthetic discharge','ca7700000000000000000000000000000000000000000000');
select pg_temp.assert_true(jsonb_array_length(public.hospital_care_workspace(:'clinic',null)->'records')=3,'discharge erased history');
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000701',2,current_setting('test.data')::jsonb,repeat('78',24))$q$,'task_not_pending');
reset role;
-- Revoked authority cannot retrieve a receipt to bypass a fresh write check.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic revoked care authority');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_care_record(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000700',1,current_setting('test.data')::jsonb,repeat('71',24))$q$,'explicit_permission_required');
reset role;set role anon;
select pg_temp.expect_error('select public.hospital_care_workspace(null,null)','permission denied');
select pg_temp.expect_error('select public.hospital_care_record(null,null,null,null,null)','permission denied');
reset role;
select pg_temp.assert_true(not(select migration_reviewed or enforcement_enabled from private.permission_policy),'cut activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
