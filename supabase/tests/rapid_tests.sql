-- Synthetic facts only; no clinical conclusions or reference ranges.
create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
create function pg_temp.expect_error(sql text,expected text) returns void language plpgsql as $$begin begin execute sql;exception when others then if position(expected in sqlerrm)>0 then return;end if;raise;end;raise exception 'Expected rejection: %',expected;end$$;
select id as clinic from public.clinics where name='Synthetic clinical permission A' \gset
select id as case_id,patient_id as patient from public.clinical_cases where clinic_id=:'clinic' and title='Synthetic case' \gset
select set_config('test.case',:'case_id',false);
select set_config('test.clinic',:'clinic',false);
select v.id as profile_version from private.professional_profile_versions v join public.professional_profiles p on p.id=v.profile_id where p.user_id='00000000-0000-0000-0000-000000000111' order by v.version desc limit 1 \gset
select private.professional_record_external(:'profile_version','00000000-0000-0000-0000-000000000114',clock_timestamp(),repeat('b',64),'Synthetic rapid-test identity',clock_timestamp()+interval '1 day');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000110',false);
set role authenticated;
select public.permission_procedure_set(:'clinic',null,'Synthetic test evaluation',true) as procedure \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select public.clinical_scope_bind(:'case_id','evaluacion',:'procedure',true,'Synthetic clinic policy','Synthetic initial binding');
select public.clinical_authorize(:'case_id',auth.uid(),'evaluacion',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('a1',24));
select pg_temp.assert_true((public.clinical_rapid_tests_workspace(:'case_id')->'actions'->>'record')::boolean=false,'role or case decision bypassed explicit grant');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,jsonb_build_object('test_name','Synthetic kit','c_band','seen','t_band','not_seen','result','Synthetic observation','observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('b1',24))$q$,'explicit_procedure_permission_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000110',false);
set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000111','procedure.perform',:'procedure',clock_timestamp()+interval '1 day','Synthetic rapid test') as grant_id \gset
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000111','clinical.attach',null,clock_timestamp()+interval '1 day','Synthetic rapid test photo') as attach_grant \gset
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select set_config('test.data',jsonb_build_object('test_name','Synthetic kit','c_band','seen','t_band','not_seen','result','Synthetic observed text','observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,false);
select pg_temp.assert_true((public.clinical_rapid_tests_workspace(:'case_id')->'actions'->>'record')::boolean,'eligible professional denied');
select public.clinical_rapid_test_add(:'case_id',current_setting('test.data')::jsonb,repeat('c1',24)) as original \gset
select pg_temp.assert_true(public.clinical_rapid_test_add(:'case_id',current_setting('test.data')::jsonb,repeat('c1',24))=:'original','retry duplicated record');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb||'{"result":"changed"}',repeat('c1',24))$q$,'operation_payload_changed');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb||'{"recorded_by":"00000000-0000-0000-0000-000000000112"}',repeat('d1',24))$q$,'rapid_test_fields_only');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb||'{"c_band":""}',repeat('d1',24))$q$,'invalid_rapid_test');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb||jsonb_build_object('observed_at',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('d1',24))$q$,'invalid_observation_time');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb||'{"c_band":"auto_positive"}',repeat('d1',24))$q$,'clinical_rapid_tests_c_band_check');
select set_config('test.photo',:'clinic'||'/'||:'case_id'||'/'||repeat('e1',24)||'-'||repeat('a',64)||'.png',false);
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb||jsonb_build_object('photo_path',current_setting('test.photo')),repeat('e1',24))$q$,'invalid_rapid_test_photo');
insert into storage.objects(bucket_id,name,owner_id,metadata) values('rapid-test-photos',current_setting('test.photo'),auth.uid()::text,'{"mimetype":"image/png","size":300}');
select pg_temp.expect_error($q$insert into storage.objects(bucket_id,name,owner_id,metadata) values('rapid-test-photos',replace(current_setting('test.photo'),repeat('e1',24),repeat('e2',24)),'00000000-0000-0000-0000-000000000112','{"mimetype":"image/png","size":300}')$q$,'row-level security');
select public.clinical_rapid_test_add(:'case_id',current_setting('test.data')::jsonb||jsonb_build_object('photo_path',current_setting('test.photo')),repeat('e1',24)) as photo_record \gset
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='rapid-test-photos' and name=current_setting('test.photo')),'registered evidence cannot be read');
update storage.objects set metadata='{}' where bucket_id='rapid-test-photos';
delete from storage.objects where bucket_id='rapid-test-photos';
select pg_temp.assert_true((select count(*)=1 and min(metadata->>'size')='300' from storage.objects where bucket_id='rapid-test-photos'),'evidence replaced or removed');
select set_config('test.correction', (current_setting('test.data')::jsonb||jsonb_build_object('replaces_id',:'original','correction_reason','Synthetic correction','result','Synthetic revised observation'))::text,false);
select public.clinical_rapid_test_add(:'case_id',current_setting('test.correction')::jsonb,repeat('f1',24)) as corrected \gset
select pg_temp.assert_true(public.clinical_rapid_test_add(:'case_id',current_setting('test.correction')::jsonb,repeat('f1',24))=:'corrected','correction retry rejected');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.correction')::jsonb,repeat('a2',24))$q$,'rapid_test_already_corrected');
select pg_temp.assert_true(jsonb_array_length(public.clinical_rapid_tests_workspace(:'case_id')->'records')=3,'history lost');
reset role;
select pg_temp.assert_true((select interpretation='' and recorded_by='00000000-0000-0000-0000-000000000111' and result='Synthetic observed text' from private.clinical_rapid_tests where id=:'original'),'interpretation inferred or original mutated');
select pg_temp.expect_error('update private.clinical_rapid_tests set result=''changed''','append_only_permission_record');
select pg_temp.assert_true(exists(select 1 from public.audit_log where entity_id=:'photo_record' and details->>'permission_grant_id'=:'grant_id'),'grant provenance missing');
-- A second case in this clinic cannot attach another case's evidence or corrections.
insert into public.form_documents(clinic_id,patient_id,version_id,responsible_id,values,branding,snapshot,created_by)
select clinic_id,patient_id,version_id,responsible_id,'{}','{}','{}',auth.uid() from public.form_documents
where id=(select document_id from public.clinical_cases where id=:'case_id') returning id as other_document \gset
insert into public.clinical_cases(clinic_id,patient_id,document_id,responsible_id,kind,title,reason,clinical_date)
values(:'clinic',:'patient',:'other_document','00000000-0000-0000-0000-000000000111','clinical_history','Synthetic other case','Synthetic',current_date) returning id as other_case \gset
set role authenticated;
select public.clinical_scope_bind(:'other_case','evaluacion',:'procedure',true,'Synthetic clinic policy','Synthetic other binding');
select public.clinical_authorize(:'other_case',auth.uid(),'evaluacion',to_char(clock_timestamp()+interval '1 day','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),repeat('b2',24));
select set_config('test.other_case',:'other_case',false);
select set_config('test.data', (current_setting('test.data')::jsonb||jsonb_build_object('observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')))::text,false);
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.other_case')::uuid,current_setting('test.data')::jsonb||jsonb_build_object('photo_path',current_setting('test.photo')),repeat('d2',24))$q$,'invalid_rapid_test_photo');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.other_case')::uuid,current_setting('test.correction')::jsonb||jsonb_build_object('observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')),repeat('c2',24))$q$,'responsible_correction_required');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000113',false);
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_rapid_tests_workspace(current_setting('test.case')::uuid)$q$,'clinical_access_denied');
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb,repeat('a3',24))$q$,'clinical_access_denied');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='rapid-test-photos'),'foreign clinic can read evidence');
select pg_temp.expect_error('select * from private.clinical_rapid_tests','permission denied');
reset role;
-- Revoke only attachment authority: recording without a photo remains permitted.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000110',false);
set role authenticated;
select public.permission_revoke(:'attach_grant','Synthetic photo revoke');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select pg_temp.assert_true((public.clinical_rapid_tests_workspace(:'case_id')->'actions'->>'record')::boolean and not (public.clinical_rapid_tests_workspace(:'case_id')->'actions'->>'photo')::boolean,'attachment permission improperly implied by evaluation');
select pg_temp.expect_error($q$insert into storage.objects(bucket_id,name,owner_id,metadata) values('rapid-test-photos',replace(current_setting('test.photo'),repeat('e1',24),repeat('e2',24)),auth.uid()::text,'{"mimetype":"image/png","size":300}')$q$,'row-level security');
select pg_temp.assert_true((select count(*)=1 from storage.objects where bucket_id='rapid-test-photos'),'photo-only revocation removed clinical read');
reset role;
-- Revocation also blocks identical retries and photo creation.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000110',false);
set role authenticated;
select public.permission_revoke(:'grant_id','Synthetic revoke');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000111',false);
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_rapid_test_add(current_setting('test.case')::uuid,current_setting('test.data')::jsonb,repeat('c1',24))$q$,'explicit_procedure_permission_required');
select pg_temp.assert_true(not private.rapid_test_photo_allowed(current_setting('test.photo'),true),'revoked performer can upload');
reset role;
insert into private.permission_revocations(grant_id,revoked_by,reason)
select g.id,'00000000-0000-0000-0000-000000000110','Synthetic clinical read revoke'
from private.member_permission_grants g where g.clinic_id=:'clinic' and g.user_id='00000000-0000-0000-0000-000000000111' and g.code='clinical.read'
and not exists(select 1 from private.permission_revocations r where r.grant_id=g.id);
set role authenticated;
select pg_temp.expect_error($q$select public.clinical_rapid_tests_workspace(current_setting('test.case')::uuid)$q$,'clinical_access_denied');
select pg_temp.assert_true((select count(*)=0 from storage.objects where bucket_id='rapid-test-photos'),'revoked clinical read still sees evidence');
reset role;
set role anon;
select pg_temp.expect_error('select public.clinical_rapid_tests_workspace(null)','permission denied');
select pg_temp.expect_error('select public.clinical_rapid_test_add(null,''{}'',null)','permission denied');
reset role;
select pg_temp.assert_true((select not public and file_size_limit=8000000 and allowed_mime_types=array['image/png','image/jpeg'] from storage.buckets where id='rapid-test-photos'),'private photo limits lost');
select pg_temp.assert_true(not(select admissions_enabled or enforcement_enabled from private.beta_policy),'beta opened');
