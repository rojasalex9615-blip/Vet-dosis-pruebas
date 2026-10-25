-- Operator-only, after schema/access review and local tests. Do not run on production by default.
-- Requires Supabase pg_cron. No network, API keys or phone credentials are used by this job.
begin;
create extension if not exists pg_cron;
select cron.schedule('vetdosis-hospital-minute','* * * * *','select private.hospital_automation_tick()');
update private.hospital_automation_runtime set enabled=true;
commit;
-- Pause: update private.hospital_automation_runtime set enabled=false;
-- Remove schedule: select cron.unschedule('vetdosis-hospital-minute');
