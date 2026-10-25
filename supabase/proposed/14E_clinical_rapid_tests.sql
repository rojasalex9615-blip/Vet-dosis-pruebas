-- LOCAL CANDIDATE ONLY. Requires 13C and Storage; no deployment or clinical defaults.
begin;
do $$begin
 if not(select not admissions_enabled and not enforcement_enabled from private.beta_policy)
 or (select enforcement_enabled from private.permission_policy) then
 raise exception 'closed_beta_and_dormant_permissions_required';end if;
end$$;

create table private.clinical_rapid_tests (
 id uuid primary key default gen_random_uuid(),
 clinic_id uuid not null, case_id uuid not null,
 test_name text not null check(length(btrim(test_name)) between 1 and 300),
 sample text not null default '' check(length(sample)<=1000),
 c_band text not null check(c_band in ('seen','not_seen','uncertain','not_applicable')),
 t_band text not null check(t_band in ('seen','not_seen','uncertain','not_applicable')),
 result text not null check(length(btrim(result)) between 1 and 4000),
 interpretation text not null default '' check(length(interpretation)<=4000),
 notes text not null default '' check(length(notes)<=4000),
 observed_at timestamptz not null,
 recorded_by uuid not null references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 photo_path text unique,
 replaces_id uuid unique references private.clinical_rapid_tests(id),
 correction_reason text,
 foreign key(clinic_id,case_id) references public.clinical_cases(clinic_id,id),
 check((replaces_id is null and correction_reason is null) or
 (replaces_id is not null and correction_reason is not null and length(btrim(correction_reason)) between 1 and 1000))
);
alter table private.clinical_rapid_tests enable row level security;
revoke all on private.clinical_rapid_tests from public,anon,authenticated;
create trigger immutable before update or delete on private.clinical_rapid_tests
 for each row execute function private.permission_immutable();

-- Separate immutable evidence bucket: existing clinical-attachments permits replacement/deletion.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('rapid-test-photos','rapid-test-photos',false,8000000,array['image/png','image/jpeg']);
create function private.rapid_test_photo_allowed(p_name text,p_write boolean)
returns boolean language plpgsql stable security definer set search_path='' as $$
declare parts text[]; c public.clinical_cases;
begin
 if auth.uid() is null then return false;end if;
 parts=string_to_array(p_name,'/');
 if array_length(parts,1)<>3 or parts[1] !~ '^[0-9a-f-]{36}$'
 or parts[2] !~ '^[0-9a-f-]{36}$' or parts[3] !~ '^[0-9a-f]{48}-[0-9a-f]{64}[.](png|jpg)$' then return false;end if;
 select * into c from public.clinical_cases where clinic_id::text=parts[1] and id::text=parts[2];
 if not found or not private.clinical_readable(c) then return false;end if;
 if not p_write then return exists(select 1 from private.clinical_rapid_tests where case_id=c.id and photo_path=p_name);end if;
 return private.clinical_eligible(c,auth.uid(),'evaluacion',clock_timestamp())
 and exists(select 1 from private.member_permission_grants g
 where g.id=private.permission_effective(c.clinic_id,auth.uid(),'clinical.attach')
 and g.valid_until>clock_timestamp());
end$$;
-- 13X normally registers this permission. This candidate can also follow 13C directly.
insert into private.permission_catalog(code,label,procedure_scoped,requires_professional)
values('clinical.attach','Adjuntar archivos al expediente clínico',false,false)
on conflict(code) do nothing;
revoke all on function private.rapid_test_photo_allowed(text,boolean) from public,anon,service_role;
grant execute on function private.rapid_test_photo_allowed(text,boolean) to authenticated;
create policy rapid_photo_read on storage.objects for select to authenticated
using(bucket_id='rapid-test-photos' and (private.rapid_test_photo_allowed(name,false)
 or (owner_id=auth.uid()::text and private.rapid_test_photo_allowed(name,true))));
create policy rapid_photo_insert on storage.objects for insert to authenticated
with check(bucket_id='rapid-test-photos' and owner_id=auth.uid()::text and private.rapid_test_photo_allowed(name,true));
-- No UPDATE/DELETE policy: registered evidence cannot be replaced or removed by clients.

create function public.clinical_rapid_tests_workspace(p_case uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare c public.clinical_cases; eligible boolean; authority boolean;
begin
 select * into c from public.clinical_cases where id=p_case;
 if not found or not private.clinical_readable(c) then raise exception 'clinical_access_denied';end if;
 eligible=private.clinical_eligible(c,auth.uid(),'evaluacion',clock_timestamp());
 authority=c.responsible_id=auth.uid() and private.clinical_professional_at(c.clinic_id,auth.uid(),clock_timestamp())
 and exists(select 1 from private.member_permission_grants g where g.id=private.permission_effective(c.clinic_id,auth.uid(),'clinical.authorize') and g.valid_until>clock_timestamp());
 return jsonb_build_object('schema_version',1,'clinic_id',c.clinic_id,'case_id',c.id,'patient_id',c.patient_id,'actor_id',auth.uid(),
 'actions',jsonb_build_object('record',eligible,'correct',eligible and authority,'photo',eligible and exists(
 select 1 from private.member_permission_grants g where g.id=private.permission_effective(c.clinic_id,auth.uid(),'clinical.attach') and g.valid_until>clock_timestamp())),
 'records',coalesce((select jsonb_agg(to_jsonb(r) order by r.observed_at desc,r.created_at desc,r.id) from private.clinical_rapid_tests r where r.case_id=c.id),'[]'));
end$$;

create function public.clinical_rapid_test_add(p_case uuid,p_data jsonb,p_operation text)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.clinical_cases; row_id uuid; previous uuid; fp jsonb; t timestamptz; photo text; k text; meta jsonb;
begin
 select * into c from public.clinical_cases where id=p_case;
 perform 1 from public.clinics where id=c.clinic_id for update;
 select * into c from public.clinical_cases where id=p_case for update;
 if not found then raise exception 'clinical_access_denied';end if;
 if jsonb_typeof(p_data) is distinct from 'object' then raise exception 'invalid_rapid_test';end if;
 if exists(select 1 from jsonb_object_keys(p_data) key where key not in
 ('test_name','sample','c_band','t_band','result','interpretation','notes','observed_at','photo_path','replaces_id','correction_reason')) then raise exception 'rapid_test_fields_only';end if;
 foreach k in array array['test_name','c_band','t_band','result','observed_at'] loop
 if jsonb_typeof(p_data->k) is distinct from 'string' or length(btrim(p_data->>k))=0 then raise exception 'invalid_rapid_test';end if;end loop;
 foreach k in array array['sample','interpretation','notes','photo_path','replaces_id','correction_reason'] loop
 if p_data ? k and jsonb_typeof(p_data->k) is distinct from 'string' then raise exception 'invalid_rapid_test';end if;end loop;
 t=private.clinical_time(p_data->>'observed_at');
 perform private.clinical_write_check(c,'evaluacion',auth.uid(),t);
 previous=(p_data->>'replaces_id')::uuid;
 if previous is not null then
 perform private.clinical_authority_require(c);
 if c.responsible_id is distinct from auth.uid() or not exists(select 1 from private.clinical_rapid_tests where id=previous and case_id=c.id)
 then raise exception 'responsible_correction_required';end if;
 elsif p_data ? 'correction_reason' then raise exception 'invalid_rapid_test';end if;
 fp=jsonb_build_object('kind','clinical_rapid_test','case',c.id,'data',p_data);
 row_id=private.vet_receipt(c.clinic_id,p_operation,fp);
 if row_id is not null then return row_id;end if;
 if previous is not null and exists(select 1 from private.clinical_rapid_tests where replaces_id=previous)
 then raise exception 'rapid_test_already_corrected';end if;
 photo=p_data->>'photo_path';
 if photo is not null then
 if not private.rapid_test_photo_allowed(photo,true) or split_part(photo,'/',1)<>c.clinic_id::text or split_part(photo,'/',2)<>c.id::text
 or split_part(split_part(photo,'/',3),'-',1)<>p_operation then raise exception 'invalid_rapid_test_photo';end if;
 select metadata into meta from storage.objects where bucket_id='rapid-test-photos' and name=photo and owner_id=auth.uid()::text for share;
 if not found or meta->>'mimetype' is distinct from (case when photo like '%.png' then 'image/png' else 'image/jpeg' end)
 or coalesce(meta->>'size','') !~ '^[0-9]{1,8}$' then raise exception 'invalid_rapid_test_photo';end if;
 if (meta->>'size')::bigint not between 1 and 8000000 then raise exception 'invalid_rapid_test_photo';end if;
 end if;
 insert into private.clinical_rapid_tests(clinic_id,case_id,test_name,sample,c_band,t_band,result,interpretation,notes,observed_at,recorded_by,photo_path,replaces_id,correction_reason)
 values(c.clinic_id,c.id,btrim(p_data->>'test_name'),coalesce(p_data->>'sample',''),p_data->>'c_band',p_data->>'t_band',btrim(p_data->>'result'),coalesce(p_data->>'interpretation',''),coalesce(p_data->>'notes',''),t,auth.uid(),photo,previous,p_data->>'correction_reason') returning id into row_id;
 insert into private.vet_operation_receipts values(auth.uid(),c.clinic_id,p_operation,fp,row_id);
 perform private.permission_event(c.clinic_id,'clinical_rapid_test_added',row_id,
 private.clinical_permission_context(c,'evaluacion',auth.uid(),t)||jsonb_build_object('case_id',c.id,'replaces_id',previous));
 return row_id;
end$$;
revoke all on function public.clinical_rapid_tests_workspace(uuid),public.clinical_rapid_test_add(uuid,jsonb,text) from public,anon,service_role;
grant execute on function public.clinical_rapid_tests_workspace(uuid),public.clinical_rapid_test_add(uuid,jsonb,text) to authenticated;
select private.beta_install_guards();
notify pgrst,'reload schema';
commit;
