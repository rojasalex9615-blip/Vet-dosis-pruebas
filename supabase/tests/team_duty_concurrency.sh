#!/usr/bin/env bash
set -euo pipefail
container_name="$1"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
cat > "$work_dir/context.sql" <<'SQL'
select id as clinic from public.clinics where name='Synthetic duty clinic' \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000009901',false);
set role authenticated;
SQL
{ cat "$work_dir/context.sql";cat <<'SQL'
begin;
select public.team_duty_save(:'clinic',auth.uid(),jsonb_build_object('kind','shift','start_day',current_date+2,'end_day',current_date+2,'start_minute',60,'end_minute',120,'zone','Etc/UTC','reason','Synthetic race'),repeat('f1',24));
select pg_advisory_xact_lock(779911);select pg_sleep(2);commit;
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/first.log" 2>&1 &
first_pid=$!
ready=false
for attempt in {1..40};do
 if [ "$(docker exec "$container_name" psql -U postgres -Atc 'select pg_try_advisory_lock(779911)')" = f ];then ready=true;break;fi
 sleep 0.1
done
if [ "$ready" != true ];then cat "$work_dir/first.log";exit 1;fi
{ cat "$work_dir/context.sql";cat <<'SQL'
select public.team_duty_save(:'clinic',auth.uid(),jsonb_build_object('kind','shift','start_day',current_date+2,'end_day',current_date+2,'start_minute',90,'end_minute',150,'zone','Etc/UTC','reason','Synthetic overlapping race'),repeat('f2',24));
SQL
} | docker exec -i "$container_name" psql -U postgres -v ON_ERROR_STOP=1 > "$work_dir/second.log" 2>&1 && { echo 'Concurrent overlap accepted';exit 1; }
wait "$first_pid" || { cat "$work_dir/first.log";exit 1; }
grep -q overlapping_schedule "$work_dir/second.log"
echo 'Concurrent overlapping shifts rejected after committed first write.'
