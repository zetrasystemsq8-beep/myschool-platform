-- MySchool: production safety check. Run in the Supabase SQL Editor of the PRODUCTION project (read-only, changes nothing).
-- Every row should say OK. Anything saying PROBLEM or REVIEW needs attention before real schools use the app.
select 'Row level security on every table' as check_name,
       case when count(*) = 0 then 'OK' else 'PROBLEM' end as status,
       coalesce(string_agg(c.relname, ', '), 'all tables protected') as detail
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'myschool' and c.relkind = 'r' and not c.relrowsecurity
union all
select 'Anonymous visitors have no table access',
       case when count(*) = 0 then 'OK' else 'PROBLEM' end,
       coalesce(string_agg(distinct table_name, ', '), 'none')
  from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'myschool'
union all
select 'Anonymous visitors can run only the school search',
       case when coalesce(array_agg(p.proname::text order by p.proname), '{}') = array['get_public_school', 'search_schools'] then 'OK' else 'PROBLEM' end,
       coalesce(string_agg(p.proname, ', ' order by p.proname), 'none')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'myschool' and has_function_privilege('anon', p.oid, 'execute')
union all
select 'Private helper functions are hidden from anonymous visitors',
       case when count(*) = 0 then 'OK' else 'PROBLEM' end,
       coalesce(string_agg(p.proname, ', '), 'none')
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'ms_private' and has_function_privilege('anon', p.oid, 'execute')
union all
select 'Every view uses the caller''s permissions',
       case when count(*) = 0 then 'OK' else 'PROBLEM' end,
       coalesce(string_agg(c.relname, ', '), 'all views safe')
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'myschool' and c.relkind = 'v' and not coalesce('security_invoker=true' = any (c.reloptions), false)
union all
select 'Only the logo bucket is public',
       case when count(*) = 0 then 'OK' else 'PROBLEM' end,
       coalesce(string_agg(id, ', '), 'none')
  from storage.buckets where public and id like 'myschool-%' and id <> 'myschool-logos'
union all
select 'No demo schools left in production',
       case when count(*) = 0 then 'OK' else 'PROBLEM' end,
       coalesce(string_agg(school_code, ', '), 'none')
  from myschool.schools where school_code like 'DEMO-%'
union all
select 'Platform administrators (should be only you and your team)',
       case when count(*) between 1 and 3 then 'OK' else 'REVIEW' end,
       count(*)::text || ' platform admin(s)'
  from myschool.profiles where is_platform_admin
union all
select 'Active schools that have no active administrator',
       case when count(*) = 0 then 'OK' else 'REVIEW' end,
       coalesce(string_agg(s.school_code, ', '), 'none')
  from myschool.schools s
 where s.is_active and not exists (select 1 from myschool.school_members m
                                    where m.school_id = s.id and m.role = 'school_admin' and m.status = 'active');
