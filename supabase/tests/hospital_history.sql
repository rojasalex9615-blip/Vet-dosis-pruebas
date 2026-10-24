-- Synthetic history only; read RPCs never generate/confirm tasks or medication.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
insert into auth.users(id,email,email_confirmed_at) values('00000000-0000-0000-0000-000000019900','history-admin@example.test',now()),('00000000-0000-0000-0000-000000019901','history-reader@example.test',now()),('00000000-0000-0000-0000-000000019902','history-outsider@example.test',now());
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000019900',false);
select public.create_clinic('Synthetic closed history') as clinic \gset
select public.create_clinic('Synthetic other history') as other \gset
select set_config('test.clinic',:'clinic',false);
select set_config('test.other',:'other',false);
insert into public.clinic_members(clinic_id,user_id,role) values(:'clinic','00000000-0000-0000-0000-000000019901','auxiliar'),(:'other','00000000-0000-0000-0000-000000019902','auxiliar');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000019901','hospital.read',null,clock_timestamp()+interval '1 day','Synthetic history read') as read_grant \gset
select set_config('test.grant',:'read_grant',false);
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values('00000000-0000-0000-0000-000000019910',:'clinic','Synthetic history patient','synthetic','sin especificar',auth.uid()),('00000000-0000-0000-0000-000000019911',:'other','Other clinic patient','synthetic','sin especificar',auth.uid());
-- Exact ties ensure pagination uses the UUID tie breaker.
insert into public.hospital_stays(id,clinic_id,patient_id,cage,admitted_by,admitted_at,discharged_at,discharged_by,discharge_reason)
select ('10000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,:'clinic','00000000-0000-0000-0000-000000019910',null,auth.uid(),now()-interval '2 days',now()-interval '1 day',auth.uid(),'Synthetic discharge' from generate_series(1,28) n;
insert into public.hospital_stays(id,clinic_id,patient_id,cage,admitted_by) values('00000000-0000-0000-0000-000000019912',:'clinic','00000000-0000-0000-0000-000000019910','Synthetic active',auth.uid());
insert into public.hospital_stays(id,clinic_id,patient_id,cage,admitted_by,discharged_at,discharge_reason) values('00000000-0000-0000-0000-000000019913',:'other','00000000-0000-0000-0000-000000019911',null,auth.uid(),now(),'Other clinic discharge');
select set_config('test.stay','10000000-0000-0000-0000-000000000028',false);
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,state,created_by,performed_by,performed_at)
select ('20000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,:'clinic',current_setting('test.stay')::uuid,'revision','Synthetic historic indication','Synthetic entered instructions',now()-interval '2 days',15,'done',auth.uid(),auth.uid(),now()-interval '2 days' from generate_series(1,53) n;
insert into public.audit_log(clinic_id,actor_id,action,entity_id,details) values(:'clinic',auth.uid(),'hospital_admitted',current_setting('test.stay'),'{"cage":null}'),(:'clinic',auth.uid(),'hospital_cage_changed',current_setting('test.stay'),'{"from":null,"to":"Synthetic box","reason":"Synthetic transfer"}');
insert into public.staff_display_names(clinic_id,user_id,name) values(:'clinic',auth.uid(),'Synthetic history admin');
select count(*) as task_count from public.hospital_tasks \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000019901',false);set role authenticated;
select public.hospital_closed_history(:'clinic') as page \gset
select set_config('test.cursor',(:'page'::jsonb->'next')::text,false);
select pg_temp.assert_true(jsonb_array_length(:'page'::jsonb->'stays')=25,'page not bounded');
select pg_temp.assert_true(:'page'::jsonb->>'actor_id'=auth.uid()::text,'wrong actor');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(:'page'::jsonb->'stays') s where s->>'clinic_id'<>current_setting('test.clinic') or s->>'discharged_at' is null),'active or foreign stay leaked');
select public.hospital_closed_history(:'clinic','',current_setting('test.cursor')::jsonb) as page2 \gset
select pg_temp.assert_true(jsonb_array_length(:'page2'::jsonb->'stays')=3 and :'page2'::jsonb->'next'='null'::jsonb,'tie pagination lost rows');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(:'page'::jsonb->'stays') a join jsonb_array_elements(:'page2'::jsonb->'stays') b on a->>'id'=b->>'id'),'pagination duplicated stays');
select pg_temp.assert_true(jsonb_array_length(public.hospital_closed_history(:'clinic','OTHER')->'stays')=0,'search leaked clinic');
select pg_temp.assert_true(jsonb_array_length(public.hospital_closed_history(:'clinic','HISTORY')->'stays')=25,'case insensitive search missing');
select pg_temp.assert_true(jsonb_array_length(public.hospital_closed_history(:'clinic','%')->'stays')=0,'wildcard interpreted');
select pg_temp.expect_error($q$select public.hospital_closed_history(current_setting('test.other')::uuid)$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.hospital_closed_detail(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000019913')$q$,'closed_stay_not_found');
select pg_temp.expect_error($q$select public.hospital_closed_detail(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000019912')$q$,'closed_stay_not_found');
select pg_temp.expect_error($q$select public.hospital_closed_history(current_setting('test.clinic')::uuid,repeat('x',101))$q$,'invalid_history_query');
select pg_temp.expect_error($q$select public.hospital_closed_history(current_setting('test.clinic')::uuid,'','{}')$q$,'invalid_history_cursor');
select public.hospital_closed_detail(:'clinic',current_setting('test.stay')::uuid) as detail \gset
select pg_temp.assert_true(jsonb_array_length(:'detail'::jsonb->'tasks')=50,'tasks page not bounded');
select pg_temp.assert_true(jsonb_array_length(:'detail'::jsonb->'events')=2,'cage events missing');
select pg_temp.assert_true(:'detail'::jsonb->'stay'->>'discharged_name'='Synthetic history admin','author name missing');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(:'detail'::jsonb->'tasks') t where t ? 'actions'),'actions exposed');
select public.hospital_closed_detail(:'clinic',current_setting('test.stay')::uuid,:'detail'::jsonb->'next') as detail2 \gset
select pg_temp.assert_true(jsonb_array_length(:'detail2'::jsonb->'tasks')=3 and :'detail2'::jsonb->'next'='null'::jsonb,'task tie pagination lost rows');
select pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(:'detail'::jsonb->'tasks') a join jsonb_array_elements(:'detail2'::jsonb->'tasks') b on a->>'id'=b->>'id'),'task pagination duplicated');
reset role;
select pg_temp.assert_true((select count(*)=:task_count from public.hospital_tasks),'history generated tasks');
-- Revocation is checked for every page and detail, including read access removed mid-browse.
insert into private.permission_revocations(grant_id,revoked_by,reason) values(:'read_grant','00000000-0000-0000-0000-000000019900','Synthetic revoke');
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_closed_history(current_setting('test.clinic')::uuid,'',current_setting('test.cursor')::jsonb)$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.hospital_closed_detail(current_setting('test.clinic')::uuid,current_setting('test.stay')::uuid)$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000019900',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_closed_history(current_setting('test.clinic')::uuid)$q$,'explicit_permission_required');
reset role;set role anon;
select pg_temp.expect_error('select public.hospital_closed_history(null)','permission denied');
select pg_temp.expect_error('select public.hospital_closed_detail(null,null)','permission denied');
reset role;set role service_role;
select pg_temp.expect_error('select public.hospital_closed_history(null)','permission denied');
reset role;
