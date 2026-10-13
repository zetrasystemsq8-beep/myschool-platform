-- pgTAP: attendance. Run with: supabase db reset && supabase test db
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
create or replace function tests.today() returns date language sql as
  $$ select (now() at time zone 'Africa/Lagos')::date $$;
grant execute on function tests.act_as(uuid), tests.today() to anon, authenticated;

-- the demo school year ended in the past; stretch it so "today" is inside it
update myschool.academic_sessions set start_date = tests.today() - 200, end_date = tests.today() + 200
 where id = 'aaaaaaaa-6000-0000-0000-000000000001';

-- ===================================================== teacher marks the register
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select is(myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today(),
  '[{"student_id":"aaaaaaaa-5000-0000-0000-000000000001","status":"present"},{"student_id":"aaaaaaaa-5000-0000-0000-000000000002","status":"late"}]'::jsonb),
  2, 'teacher marks present and late for their class');
select is(myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today(),
  '[{"student_id":"aaaaaaaa-5000-0000-0000-000000000001","status":"absent"}]'::jsonb),
  1, 'marking again corrects the record');
select is((select count(*)::int from myschool.attendance_records where class_id = 'aaaaaaaa-7000-0000-0000-000000000001' and attendance_date = tests.today()),
  2, 'no duplicate rows for the same student, class and day');
select is((select status::text from myschool.attendance_records where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and attendance_date = tests.today()),
  'absent', 'the correction was applied');
select is((select late from myschool.attendance_daily_summary where class_id = 'aaaaaaaa-7000-0000-0000-000000000001' and attendance_date = tests.today()), 1, 'daily summary counts late');
select is((select absent from myschool.attendance_daily_summary where class_id = 'aaaaaaaa-7000-0000-0000-000000000001' and attendance_date = tests.today()), 1, 'daily summary counts absent');
select throws_ok($$select myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today() - 10, '[{"student_id":"aaaaaaaa-5000-0000-0000-000000000001","status":"present"}]'::jsonb)$$,
  '42501', null, 'teacher cannot change records older than 7 days');
select throws_ok($$select myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today() + 1, '[{"student_id":"aaaaaaaa-5000-0000-0000-000000000001","status":"present"}]'::jsonb)$$,
  '42501', null, 'teacher cannot mark a future day');
select throws_ok($$select myschool.mark_attendance('bbbbbbbb-7000-0000-0000-000000000001', tests.today(), '[{"student_id":"bbbbbbbb-5000-0000-0000-000000000001","status":"present"}]'::jsonb)$$,
  '42501', null, 'teacher cannot mark another school''s class');
select throws_ok($$select myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today(), '[{"student_id":"bbbbbbbb-5000-0000-0000-000000000001","status":"present"}]'::jsonb)$$,
  '23514', null, 'a student who is not in the class cannot be marked');
select throws_ok($$insert into myschool.attendance_records (school_id, class_id, student_id, attendance_date, status) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-7000-0000-0000-000000000001','aaaaaaaa-5000-0000-0000-000000000001', tests.today() - 1, 'present')$$,
  '42501', null, 'clients cannot write the table directly');
select throws_ok($$update myschool.attendance_records set status = 'present'$$, '42501', null, 'clients cannot update the table directly');
reset role;

select throws_ok($$insert into myschool.attendance_records (school_id, class_id, student_id, attendance_date, status) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-7000-0000-0000-000000000001','aaaaaaaa-5000-0000-0000-000000000001', tests.today(), 'present')$$,
  '23505', null, 'the database itself rejects a duplicate (student, class, date)');

-- ===================================================== admin
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select is(myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today() - 10,
  '[{"student_id":"aaaaaaaa-5000-0000-0000-000000000001","status":"present"}]'::jsonb), 1, 'admin can correct an older day');
select throws_ok($$select myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today() + 1, '[{"student_id":"aaaaaaaa-5000-0000-0000-000000000001","status":"present"}]'::jsonb)$$,
  '23514', null, 'nobody can mark a future day');
select ok((select count(*)::int from myschool.attendance_records) >= 3, 'admin sees the school''s records');
reset role;
select ok(exists (select 1 from myschool.audit_logs where action = 'attendance.marked'), 'marking attendance is audited');

-- ===================================================== who can read
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- Ada's parent
select is((select count(*)::int from myschool.attendance_records where student_id = 'aaaaaaaa-5000-0000-0000-000000000001'), 2, 'parent sees their child''s attendance');
select is((select count(*)::int from myschool.attendance_records where student_id = 'aaaaaaaa-5000-0000-0000-000000000002'), 0, 'parent does not see another child''s attendance');
select is((select count(*)::int from myschool.attendance_daily_summary), 0, 'parents do not get class summaries');
select throws_ok($$select myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today(), '[{"student_id":"aaaaaaaa-5000-0000-0000-000000000001","status":"present"}]'::jsonb)$$,
  '42501', null, 'parents cannot mark attendance');
reset role;
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000002');   -- Bayo
select is((select count(*)::int from myschool.attendance_records), 1, 'a student sees only their own attendance');
reset role;
select tests.act_as('bbbbbbbb-2000-0000-0000-000000000001');   -- teacher B
select is((select count(*)::int from myschool.attendance_records where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'another school''s teacher sees no attendance');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select is((select count(*)::int from myschool.attendance_records where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'another school''s admin sees no attendance');
select throws_ok($$select myschool.mark_attendance('aaaaaaaa-7000-0000-0000-000000000001', tests.today(), '[{"student_id":"aaaaaaaa-5000-0000-0000-000000000001","status":"present"}]'::jsonb)$$,
  '42501', null, 'another school''s admin cannot mark our class');
reset role;

select * from finish();
rollback;
