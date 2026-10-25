#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
wait_marker(){
 for attempt in {1..40};do
  if [ "$(docker exec "$container_name" psql -U postgres -Atc "select pg_try_advisory_lock($1)")" = f ];then return;fi
  sleep 0.1
 done
 echo 'Care concurrency coordination failed';exit 1
}
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select id as procedure from private.procedure_types where clinic_id=:'clinic' and name='Synthetic structured care' \gset
insert into private.member_permission_grants(id,clinic_id,user_id,member_since,code,procedure_id,granted_by,valid_until,reason)
select '00000000-0000-0000-0000-000000000740',m.clinic_id,m.user_id,m.created_at,'procedure.perform',:'procedure','00000000-0000-0000-0000-000000000150',clock_timestamp()+interval '1 day','Synthetic concurrency care' from public.clinic_members m where m.clinic_id=:'clinic' and m.user_id='00000000-0000-0000-0000-000000000151';
insert into public.hospital_stays(id,clinic_id,patient_id,admitted_by,admitted_at) values('00000000-0000-0000-0000-000000000730',:'clinic','00000000-0000-0000-0000-000000000700','00000000-0000-0000-0000-000000000151',clock_timestamp()-interval '1 hour');
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,procedure_type_id,authority_grant_id)
select x.id,t.clinic_id,'00000000-0000-0000-0000-000000000730',t.kind,'Synthetic concurrent care','Synthetic',clock_timestamp()-interval '1 minute',15,t.created_by,t.procedure_type_id,t.authority_grant_id from public.hospital_tasks t cross join (values('00000000-0000-0000-0000-000000000731'::uuid),('00000000-0000-0000-0000-000000000732'::uuid)) x(id) where t.id='00000000-0000-0000-0000-000000000700';
SQL
cat > "$work_dir/context.sql" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select jsonb_build_object('care_kind','equipment_change','findings','Synthetic observed device','observed_at',to_char(clock_timestamp(),'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'confirmed',true) as data \gset
SQL
# Two sessions share a task version. The first confirmation/result commits atomically.
{ cat "$work_dir/context.sql";cat <<'SQL'
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);set local role authenticated;
select public.hospital_care_record(:'clinic','00000000-0000-0000-0000-000000000731',1,:'data','ca0100000000000000000000000000000000000000000000');
select pg_advisory_xact_lock(771190);select pg_sleep(2);commit;
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 &
first_pid=$!
wait_marker 771190
if { cat "$work_dir/context.sql";cat <<'SQL'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.hospital_care_record(:'clinic','00000000-0000-0000-0000-000000000731',1,:'data','ca0200000000000000000000000000000000000000000000');
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/second.log" 2>&1;then echo 'Concurrent second outcome accepted';exit 1;fi
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
# Observation may have been entered after the winning confirmation, or version is stale.
grep -Eq 'task_version_conflict|invalid_care_observation_time' "$work_dir/second.log" || { cat "$work_dir/second.log";exit 1; }
# A revocation holding the clinic lock must deny the queued write.
{ cat "$work_dir/context.sql";cat <<'SQL'
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',true);set local role authenticated;
select public.permission_revoke('00000000-0000-0000-0000-000000000740','Synthetic queued revocation');
select pg_advisory_xact_lock(771191);select pg_sleep(2);commit;
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 &
revoke_pid=$!
wait_marker 771191
if { cat "$work_dir/context.sql";cat <<'SQL'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.hospital_care_record(:'clinic','00000000-0000-0000-0000-000000000732',1,:'data','ca0300000000000000000000000000000000000000000000');
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/denied.log" 2>&1;then echo 'Queued revoked care accepted';exit 1;fi
wait "$revoke_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/denied.log" || { cat "$work_dir/denied.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if (select count(*) from private.hospital_care_results where task_id='00000000-0000-0000-0000-000000000731')<>1 or not exists(select 1 from public.hospital_tasks where id='00000000-0000-0000-0000-000000000731' and state='done' and version=2) then raise exception 'non_atomic_or_duplicate_result';end if;
 if exists(select 1 from private.hospital_care_results where task_id='00000000-0000-0000-0000-000000000732') or not exists(select 1 from public.hospital_tasks where id='00000000-0000-0000-0000-000000000732' and state='pending' and version=1) then raise exception 'revoked_partial_result';end if;
end$$;
SQL
echo 'Care concurrency passed: one atomic outcome; queued revocation denies task and result.'
