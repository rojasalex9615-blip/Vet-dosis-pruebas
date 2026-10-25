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
 echo 'Automation concurrency coordination failed';exit 1
}
cat > "$work_dir/context.sql" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
SQL
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/setup.log" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
insert into public.vet_patients(id,clinic_id,name,species,sex,created_by) values('00000000-0000-0000-0000-000000000880',:'clinic','Synthetic automation race patient','synthetic','sin especificar','00000000-0000-0000-0000-000000000150');
insert into public.hospital_stays(id,clinic_id,patient_id,admitted_by,admitted_at) values('00000000-0000-0000-0000-000000000880',:'clinic','00000000-0000-0000-0000-000000000880','00000000-0000-0000-0000-000000000151',clock_timestamp()-interval '1 day');
insert into private.hospital_daily_orders(id,clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,label,instructions,first_day,last_day,zone,minutes,escalation_minutes,created_at,version)
select '00000000-0000-0000-0000-000000000880',clinic_id,'00000000-0000-0000-0000-000000000880',procedure_id,author_id,private.permission_effective(clinic_id,author_id,'hospital.schedule'),read_grant,'Synthetic worker race','Synthetic',current_date+1,current_date+1,'Etc/UTC',array[600],1,clock_timestamp()-interval '1 day',1 from private.hospital_daily_orders where clinic_id=:'clinic' order by created_at,id limit 1;
SQL
# Concurrent workers must generate only one task for the same order/instant.
{ cat "$work_dir/context.sql";cat <<'SQL'
begin;select private.hospital_automation_clinic(:'clinic');
select pg_advisory_xact_lock(771200);select pg_sleep(2);commit;
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/worker.log" 2>&1 &
first_pid=$!
wait_marker 771200
{ cat "$work_dir/context.sql";echo "select private.hospital_automation_clinic(:'clinic');"; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/second.log" 2>&1 || { cat "$work_dir/second.log";exit 1; }
wait "$first_pid" || { cat "$work_dir/worker.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin if (select count(*) from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000880')<>1 then raise exception 'duplicate_worker_generation';end if;end$$;
insert into private.hospital_daily_orders(id,clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,label,instructions,first_day,last_day,zone,minutes,escalation_minutes,created_at,version)
select '00000000-0000-0000-0000-000000000881',clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,'Synthetic stopped race','Synthetic',first_day,last_day,zone,minutes,escalation_minutes,created_at,1 from private.hospital_daily_orders where id='00000000-0000-0000-0000-000000000880';
SQL
# Cancellation wins the lock: queued generation must not create any task.
{ cat "$work_dir/context.sql";cat <<'SQL'
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',true);set local role authenticated;
select public.hospital_daily_order_stop(:'clinic','00000000-0000-0000-0000-000000000881','Synthetic concurrent stop','da0100000000000000000000000000000000000000000000');
select pg_advisory_xact_lock(771201);select pg_sleep(2);commit;
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/stop.log" 2>&1 &
stop_pid=$!
wait_marker 771201
{ cat "$work_dir/context.sql";echo "select private.hospital_automation_clinic(:'clinic');"; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/stopped-worker.log" 2>&1 || { cat "$work_dir/stopped-worker.log";exit 1; }
wait "$stop_pid" || { cat "$work_dir/stop.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/ack-setup.log" <<'SQL'
do $$begin if exists(select 1 from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000881') then raise exception 'cancelled_order_generated';end if;end$$;
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',false);set role authenticated;
select public.permission_grant(:'clinic','00000000-0000-0000-0000-000000000160','hospital.report',null,clock_timestamp()+interval '1 day','Synthetic concurrent acknowledgement');
reset role;
insert into public.hospital_tasks(id,clinic_id,stay_id,kind,label,instructions,due_at,escalation_minutes,created_by,procedure_type_id,authority_grant_id)
select '00000000-0000-0000-0000-000000000882',clinic_id,stay_id,'revision','Synthetic ack race','Synthetic',clock_timestamp()-interval '5 minutes',1,author_id,procedure_id,schedule_grant from private.hospital_daily_orders where id='00000000-0000-0000-0000-000000000880';
insert into private.hospital_notices(id,clinic_id,task_id,route_id,stage,recipient_id,member_since)
select '00000000-0000-0000-0000-000000000882',clinic_id,'00000000-0000-0000-0000-000000000882',id,'primary',primary_user,primary_member_since from private.hospital_notice_routes where clinic_id=:'clinic' order by created_at desc,id desc limit 1;
SQL
# A committed acknowledgement suppresses a queued escalation, without performing the task.
{ cat "$work_dir/context.sql";cat <<'SQL'
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',true);set local role authenticated;
select public.hospital_notice_ack(:'clinic','00000000-0000-0000-0000-000000000882','Synthetic concurrent response','da0200000000000000000000000000000000000000000000');
select pg_advisory_xact_lock(771202);select pg_sleep(2);commit;
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/ack.log" 2>&1 &
ack_pid=$!
wait_marker 771202
{ cat "$work_dir/context.sql";echo "select private.hospital_automation_clinic(:'clinic');"; } | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/escalate.log" 2>&1 || { cat "$work_dir/escalate.log";exit 1; }
wait "$ack_pid" || { cat "$work_dir/ack.log";exit 1; }
docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
do $$begin
 if exists(select 1 from private.hospital_notices where task_id='00000000-0000-0000-0000-000000000882' and stage='mvz') then raise exception 'acknowledged_task_escalated';end if;
 if not exists(select 1 from public.hospital_tasks where id='00000000-0000-0000-0000-000000000882' and state='pending' and performed_at is null) then raise exception 'ack_performed_care';end if;
end$$;
SQL
echo 'Automation concurrency passed: unique generation, stop prevents queued generation, acknowledgement suppresses queued escalation.'
