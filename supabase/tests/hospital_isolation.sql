-- Synthetic operational protocol; contains no medical instruction.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;
 raise exception 'Expected rejection: %',expected;
end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('test.clinic',:'clinic',false);
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values
 ('00000000-0000-0000-0000-000000000600',:'clinic','Synthetic isolation patient','synthetic','sin especificar','00000000-0000-0000-0000-000000000150'),
 ('00000000-0000-0000-0000-000000000601',:'clinic','Synthetic next occupant','synthetic','sin especificar','00000000-0000-0000-0000-000000000150');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select pg_temp.expect_error(format('select public.hospital_snapshot(%L)',:'clinic'),'explicit_permission_required');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','hospital.manage',null,now()+interval '1 day','Synthetic admission');
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000151','hospital.isolation.manage',null,now()+interval '1 day','Synthetic isolation') as manager \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000160','hospital.isolation.handle',null,now()+interval '1 day','Synthetic handler') as handler \gset
select pg_temp.expect_error(format('select public.permission_grant(%L,''00000000-0000-0000-0000-000000000163'',''hospital.isolation.manage'',null,now()+interval ''1 day'',''Synthetic'')',:'clinic'),'verified_professional_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.hospital_admit(:'clinic','00000000-0000-0000-0000-000000000600','Synthetic Iso A',repeat('e0',24)) as stay \gset
select set_config('test.iso_stay',:'stay',false);
select pg_temp.expect_error($q$select public.hospital_isolation_set(current_setting('test.clinic')::uuid,current_setting('test.iso_stay')::uuid,1,true,'Synthetic','Synthetic v1','[]',repeat('e1',24))$q$,'isolation_protocol_required');
select pg_temp.expect_error($q$select public.hospital_isolation_set(current_setting('test.clinic')::uuid,current_setting('test.iso_stay')::uuid,1,true,'Synthetic','Synthetic v1','["A","A"]',repeat('e1',24))$q$,'isolation_steps_invalid');
select public.hospital_isolation_set(:'clinic',:'stay',1,true,'Synthetic decision','Synthetic document v1 p1','["Synthetic step A","Synthetic step B"]',repeat('e1',24));
select public.hospital_isolation_set(:'clinic',:'stay',1,true,'Synthetic decision','Synthetic document v1 p1','["Synthetic step A","Synthetic step B"]',repeat('e1',24));
select pg_temp.assert_true((public.hospital_snapshot(:'clinic')->'capabilities'->>'isolation_version')::int=1,'capability missing');
select pg_temp.assert_true((public.hospital_snapshot(:'clinic')->'isolations'->0->>'active')::boolean,'flag missing');
select pg_temp.expect_error($q$select public.hospital_isolation_set(current_setting('test.clinic')::uuid,current_setting('test.iso_stay')::uuid,1,false,'Synthetic','Synthetic document v1 p1','["Synthetic step A","Synthetic step B"]',repeat('e2',24))$q$,'hospital_version_conflict');
select pg_temp.expect_error($q$select public.hospital_isolation_set(current_setting('test.clinic')::uuid,current_setting('test.iso_stay')::uuid,2,false,'Synthetic','changed','["A"]',repeat('e2',24))$q$,'isolation_protocol_snapshot_immutable');
reset role;
select pg_temp.assert_true((select version=2 from public.hospital_stays where id=:'stay'),'retry changed version');
select id as area from private.hospital_isolation_areas where stay_id=:'stay' \gset
select set_config('test.iso_area',:'area',false);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_isolation_set(current_setting('test.clinic')::uuid,current_setting('test.iso_stay')::uuid,2,false,'Synthetic','Synthetic','["A"]',repeat('e2',24))$q$,'explicit_permission_required');
select public.hospital_isolation_enter(:'clinic',:'stay',2,'Synthetic own access',repeat('e3',24));
select public.hospital_isolation_enter(:'clinic',:'stay',2,'Synthetic own access',repeat('e3',24));
select pg_temp.expect_error($q$select public.hospital_isolation_clean(current_setting('test.clinic')::uuid,current_setting('test.iso_area')::uuid,'["Synthetic step A","Synthetic step B"]','',repeat('e4',24))$q$,'isolation_area_not_released');
select pg_temp.expect_error('select * from private.hospital_isolation_areas','permission denied');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
-- A display-only capitalization change must not release an occupied area.
select public.hospital_cage_set(:'clinic',:'stay',2,'SYNTHETIC ISO A','Synthetic spelling',repeat('ea',24));
reset role;
select pg_temp.assert_true((select count(*)=1 and bool_and(released_at is null) from private.hospital_isolation_areas where stay_id=:'stay'),'same physical cage released');
set role authenticated;
select public.hospital_cage_set(:'clinic',:'stay',3,'Synthetic Iso B','Synthetic move',repeat('e5',24));
select pg_temp.expect_error($q$select public.hospital_admit(current_setting('test.clinic')::uuid,'00000000-0000-0000-0000-000000000601',' synthetic ISO a ',repeat('e6',24))$q$,'isolation_cleaning_required');
select public.hospital_isolation_set(:'clinic',:'stay',4,false,'Synthetic withdrawal','Synthetic document v1 p1','["Synthetic step A","Synthetic step B"]',repeat('e7',24));
select public.hospital_cage_set(:'clinic',:'stay',5,null,'Synthetic unassigned',repeat('e8',24));
select public.hospital_isolation_set(:'clinic',:'stay',6,true,'Synthetic renewed decision','Synthetic document v1 p1','["Synthetic step A","Synthetic step B"]',repeat('e9',24));
select public.hospital_discharge_preview(:'clinic',:'stay') as preview \gset
select public.hospital_discharge_confirm(:'clinic',:'stay',(:'preview'::jsonb->>'version')::int,:'preview'::jsonb->>'pending_hash','Synthetic discharge',repeat('eb',24));
reset role;
select pg_temp.assert_true((select count(*)=3 and bool_and(released_at is not null) from private.hospital_isolation_areas where stay_id=:'stay'),'lost cage or unassigned cleanup at discharge');
select pg_temp.assert_true((select count(*)=1 from public.audit_log where entity_id=:'stay' and action='hospital_isolation_entry' and actor_id='00000000-0000-0000-0000-000000000160'),'entry duplicate or wrong author');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_revoke(:'handler','Synthetic revoked handler');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_isolation_enter(current_setting('test.clinic')::uuid,current_setting('test.iso_stay')::uuid,2,'Synthetic own access',repeat('e3',24))$q$,'explicit_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000160','hospital.isolation.handle',null,now()+interval '1 day','Synthetic restored handler');reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select pg_temp.expect_error($q$select public.hospital_isolation_clean(current_setting('test.clinic')::uuid,current_setting('test.iso_area')::uuid,'["Synthetic step A"]','',repeat('ec',24))$q$,'isolation_checklist_incomplete');
select public.hospital_isolation_clean(:'clinic',:'area','["Synthetic step A","Synthetic step B"]','Synthetic confirmation',repeat('ed',24));
select public.hospital_isolation_clean(:'clinic',:'area','["Synthetic step A","Synthetic step B"]','Synthetic confirmation',repeat('ed',24));
select pg_temp.assert_true(jsonb_array_length(public.hospital_isolation_history(:'clinic',:'stay'))>=8,'lost audit');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.hospital_admit(:'clinic','00000000-0000-0000-0000-000000000601','synthetic iso a',repeat('ee',24)) as next_stay \gset
select public.hospital_discharge_preview(:'clinic',:'next_stay') as next_preview \gset
select public.hospital_discharge_confirm(:'clinic',:'next_stay',(:'next_preview'::jsonb->>'version')::int,:'next_preview'::jsonb->>'pending_hash','Synthetic discharge',repeat('ef',24));
reset role;
-- The existing admin audit table policy must not bypass hospital.read for new isolation events.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select pg_temp.assert_true((select count(*)=0 from public.audit_log where clinic_id=:'clinic' and action like 'hospital_isolation_%'),'admin audit bypassed hospital.read');
reset role;
-- A member of another clinic has no access to the original clinic.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000153',false);
select public.create_clinic('Synthetic other isolation clinic') as other_clinic \gset
set role authenticated;
select pg_temp.expect_error($q$select public.hospital_isolation_history(current_setting('test.clinic')::uuid,null)$q$,'explicit_permission_required');
select pg_temp.expect_error($q$select public.hospital_isolation_clean(current_setting('test.clinic')::uuid,current_setting('test.iso_area')::uuid,'[]','',repeat('ff',24))$q$,'explicit_permission_required');
reset role;set role anon;
select pg_temp.expect_error('select public.hospital_isolation_set(null,null,null,null,null,null,null,null)','permission denied');
select pg_temp.expect_error('select public.hospital_isolation_enter(null,null,null,null,null)','permission denied');
select pg_temp.expect_error('select public.hospital_isolation_clean(null,null,null,null,null)','permission denied');
select pg_temp.expect_error('select public.hospital_isolation_history(null,null)','permission denied');
reset role;
select pg_temp.assert_true(not(select migration_reviewed or enforcement_enabled from private.permission_policy),'cut activated');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
