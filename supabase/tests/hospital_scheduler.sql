create function pg_temp.assert_true(v boolean,msg text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'ASSERT: %',msg;end if;end$$;
-- Only the local isolated PostgreSQL harness. No client/app invokes the generator here.
select pg_temp.assert_true(exists(select 1 from cron.job where jobname='vetdosis-hospital-minute' and schedule='* * * * *' and command='select private.hospital_automation_tick()' and active),'operator minute schedule missing');
-- Accelerate the same job for this test, then restore/remove it with the disposable DB.
select cron.schedule('vetdosis-hospital-minute','1 second','select private.hospital_automation_tick()');
insert into private.hospital_daily_orders(id,clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,label,instructions,first_day,last_day,zone,minutes,escalation_minutes,created_at,version)
select '00000000-0000-0000-0000-000000000890',clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,'Synthetic cron generated','Synthetic',first_day,last_day,zone,array[605],escalation_minutes,created_at,1 from private.hospital_daily_orders where id='00000000-0000-0000-0000-000000000880';
do $$declare attempt integer;begin
 for attempt in 1..120 loop
 if exists(select 1 from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000890') then return;end if;
 perform pg_sleep(0.25);
 end loop;
 raise exception 'scheduled_generation_timeout';
end$$;
select pg_temp.assert_true((select count(*)=1 from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000890' and state='pending' and medication_record_id is null),'cron did not generate exactly one review');
select pg_temp.assert_true((select last_run_at is not null from private.hospital_automation_runtime),'cron heartbeat missing');
update private.hospital_automation_runtime set enabled=false;
insert into private.hospital_daily_orders(id,clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,label,instructions,first_day,last_day,zone,minutes,escalation_minutes,created_at,version)
select '00000000-0000-0000-0000-000000000891',clinic_id,stay_id,procedure_id,author_id,schedule_grant,read_grant,'Synthetic paused cron','Synthetic',first_day,last_day,zone,array[610],escalation_minutes,created_at,1 from private.hospital_daily_orders where id='00000000-0000-0000-0000-000000000880';
select pg_sleep(2);
select pg_temp.assert_true(not exists(select 1 from public.hospital_tasks where daily_order_id='00000000-0000-0000-0000-000000000891'),'paused scheduler generated care');
select cron.unschedule('vetdosis-hospital-minute');
select pg_temp.assert_true(not exists(select 1 from public.audit_log where action='hospital_automation_failed'),'scheduled worker recorded errors');
