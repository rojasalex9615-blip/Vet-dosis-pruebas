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
 echo 'Isolation concurrency coordination failed';exit 1
}
cat > "$work_dir/context.sql" <<'SQL'
select id as clinic from public.clinics where name='Synthetic medication permissions' \gset
select a.id as area from private.hospital_isolation_areas a where a.clinic_id=:'clinic' and a.cage='Synthetic Iso B' and a.cleaned_at is null \gset
SQL
# Cleaning holds the clinic lock. Admission can only succeed after its confirmation commits.
{ cat "$work_dir/context.sql";cat <<'SQL'
begin;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',true);set local role authenticated;
select public.hospital_isolation_clean(:'clinic',:'area','["Synthetic step A","Synthetic step B"]','Synthetic concurrent cleaning',repeat('f0',24));
select pg_advisory_xact_lock(771180);select pg_sleep(2);commit;
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/clean.log" 2>&1 &
clean_pid=$!
wait_marker 771180
{ cat "$work_dir/context.sql";cat <<'SQL'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000151',false);set role authenticated;
select public.hospital_admit(:'clinic','00000000-0000-0000-0000-000000000601','Synthetic Iso B',repeat('f1',24));
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/admit.log" 2>&1 || { cat "$work_dir/admit.log";exit 1; }
wait "$clean_pid" || { cat "$work_dir/clean.log";exit 1; }
# A permission revocation that gets the lock first denies a queued cleanup, including retries.
{ cat "$work_dir/context.sql" | sed '/select a.id/d';cat <<'SQL'
begin;
select id as handler from private.member_permission_grants where clinic_id=:'clinic' and user_id='00000000-0000-0000-0000-000000000160' and code='hospital.isolation.handle' and not exists(select 1 from private.permission_revocations r where r.grant_id=member_permission_grants.id) \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000150',true);set local role authenticated;
select public.permission_revoke(:'handler','Synthetic concurrent revocation');
select pg_advisory_xact_lock(771181);select pg_sleep(2);commit;
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/revoke.log" 2>&1 &
revoke_pid=$!
wait_marker 771181
if { cat "$work_dir/context.sql" | sed '/select a.id/d';cat <<'SQL'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000160',false);set role authenticated;
select public.hospital_isolation_clean(:'clinic',null,'[]','Synthetic',repeat('f2',24));
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/denied.log" 2>&1;then echo 'Queued revoked handler was accepted';exit 1;fi
wait "$revoke_pid" || { cat "$work_dir/revoke.log";exit 1; }
grep -Fq explicit_permission_required "$work_dir/denied.log" || { cat "$work_dir/denied.log";exit 1; }
echo 'Isolation concurrency passed: reuse waits for committed cleanup; queued revocation denies action.'
