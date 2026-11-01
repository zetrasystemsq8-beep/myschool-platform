-- pgTAP: structural security checks that must keep holding as the system grows.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

create schema if not exists tests;
grant usage on schema tests to anon, authenticated;
create or replace function tests.act_as(p_uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  perform set_config('role', 'authenticated', true);
end $$;
create or replace function tests.act_anon() returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('role', 'anon', true);
end $$;
grant execute on function tests.act_as(uuid), tests.act_anon() to anon, authenticated;

select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'myschool' and c.relkind = 'r' and not c.relrowsecurity), 0,
  'every table in the myschool schema has row level security switched on');
select is((select count(*)::int from information_schema.role_table_grants where grantee = 'anon' and table_schema = 'myschool'), 0,
  'anonymous visitors have no table privileges at all');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'myschool' and c.relkind = 'v' and not coalesce('security_invoker=true' = any (c.reloptions), false)), 0,
  'every view applies the caller''s own permissions');
select is((select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'myschool' and has_function_privilege('anon', p.oid, 'execute')),
  array['get_public_school', 'search_schools'], 'anonymous visitors can only run the two public school-search functions');
select is((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'ms_private' and has_function_privilege('anon', p.oid, 'execute')), 0,
  'anonymous visitors can run none of the private helper functions');

select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- even a school admin
select throws_ok($$select * from myschool.student_login_attempts$$, '42501', null, 'signed-in users cannot read login attempts');
select throws_ok($$insert into myschool.student_login_attempts (key) values ('x')$$, '42501', null, 'signed-in users cannot write login attempts');
reset role;
select tests.act_anon();
select throws_ok($$select * from myschool.student_login_attempts$$, '42501', null, 'anonymous visitors cannot read login attempts');
reset role;

select * from finish();
rollback;
