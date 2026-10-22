-- pgTAP: student status changes and moving classes up a school year.
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
grant execute on function tests.act_as(uuid) to anon, authenticated;

-- fixtures: two more school years and a higher class in school A
insert into myschool.academic_sessions (id, school_id, name, start_date, end_date) values
 ('aaaaaaaa-6000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', '2026/2027', '2026-09-07', '2027-07-23'),
 ('aaaaaaaa-6000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', '2027/2028', '2027-09-06', '2028-07-21');
insert into myschool.classes (id, school_id, name) values ('aaaaaaaa-7000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'JSS 2 A');

-- ===================================================== student status
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select lives_ok($$select myschool.set_student_status('aaaaaaaa-5000-0000-0000-000000000002', 'withdrawn', 'Moved abroad')$$, 'admin withdraws a student');
reset role;
select is((select status::text from myschool.students where id = 'aaaaaaaa-5000-0000-0000-000000000002'), 'withdrawn', 'the status changed');
select is((select status::text from myschool.school_members where user_id = 'aaaaaaaa-3000-0000-0000-000000000002'), 'suspended', 'a withdrawn student can no longer sign in');
select is((select status::text from myschool.enrollments where student_id = 'aaaaaaaa-5000-0000-0000-000000000002'), 'withdrawn', 'and leaves the class list');
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000002');   -- Bayo, now withdrawn
select is((select count(*)::int from myschool.students), 0, 'the withdrawn student sees nothing');
reset role;
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select lives_ok($$select myschool.set_student_status('aaaaaaaa-5000-0000-0000-000000000002', 'transferred', 'Moved school')$$, 'admin marks the student as transferred');
select lives_ok($$select myschool.set_student_status('aaaaaaaa-5000-0000-0000-000000000002', 'active', 'Came back')$$, 'admin reactivates the student');
reset role;
select is((select status::text from myschool.school_members where user_id = 'aaaaaaaa-3000-0000-0000-000000000002'), 'active', 'sign-in is restored');
select is((select status::text from myschool.enrollments where student_id = 'aaaaaaaa-5000-0000-0000-000000000002'), 'active', 'and the class place is restored');
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select lives_ok($$select myschool.set_student_status('aaaaaaaa-5000-0000-0000-000000000001', 'graduated', 'Finished')$$, 'admin graduates a student');
reset role;
select is((select status::text from myschool.school_members where user_id = 'aaaaaaaa-3000-0000-0000-000000000001'), 'active', 'a graduate can still sign in to see results');
select lives_ok($$update myschool.students set status = 'active' where id = 'aaaaaaaa-5000-0000-0000-000000000001'$$, 'fixture: back to active');
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher
select throws_ok($$select myschool.set_student_status('aaaaaaaa-5000-0000-0000-000000000001', 'withdrawn', 'x')$$, '42501', null, 'a teacher cannot change a student''s status');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select throws_ok($$select myschool.set_student_status('aaaaaaaa-5000-0000-0000-000000000001', 'withdrawn', 'x')$$, '42501', null, 'another school''s admin cannot either');
reset role;

-- ===================================================== promotion
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select is(myschool.promote_class('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000002',
  'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000002', array['aaaaaaaa-5000-0000-0000-000000000002']::uuid[]),
  '{"promoted": 1, "repeated": 1, "graduated": 0, "skipped": 0}'::jsonb, 'one student moves up and one repeats');
select is(myschool.promote_class('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000002',
  'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000002', '{}'::uuid[]),
  '{"promoted": 0, "repeated": 0, "graduated": 0, "skipped": 0}'::jsonb, 'running it again changes nothing');
select throws_ok($$select myschool.promote_class('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000001', null, '{}')$$, '22023', null, 'the two school years must differ');
select is(myschool.promote_class('aaaaaaaa-6000-0000-0000-000000000002', 'aaaaaaaa-6000-0000-0000-000000000003',
  'aaaaaaaa-7000-0000-0000-000000000002', null, '{}'::uuid[]),
  '{"promoted": 0, "repeated": 0, "graduated": 1, "skipped": 0}'::jsonb, 'a class can graduate');
reset role;
select is((select class_id::text from myschool.enrollments where student_id = 'aaaaaaaa-5000-0000-0000-000000000002' and session_id = 'aaaaaaaa-6000-0000-0000-000000000002'),
  'aaaaaaaa-7000-0000-0000-000000000001', 'the repeating student stays in the same class');
select is((select status::text from myschool.enrollments where student_id = 'aaaaaaaa-5000-0000-0000-000000000001' and session_id = 'aaaaaaaa-6000-0000-0000-000000000001'), 'promoted', 'the old enrollment is marked promoted');
select is((select status::text from myschool.enrollments where student_id = 'aaaaaaaa-5000-0000-0000-000000000002' and session_id = 'aaaaaaaa-6000-0000-0000-000000000001'), 'repeated', 'and the repeater''s old one is marked repeated');
select is((select status::text from myschool.students where id = 'aaaaaaaa-5000-0000-0000-000000000001'), 'graduated', 'the graduating student is marked graduated');

-- ===================================================== teachers carry over
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select is(myschool.copy_teaching_assignments('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000002'), 2, 'the teacher keeps both subjects in the new year');
select is(myschool.copy_teaching_assignments('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000002'), 0, 'copying again adds nothing');
reset role;

-- ===================================================== who may do it
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');
select throws_ok($$select myschool.promote_class('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000002', 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000002', '{}')$$, '42501', null, 'a teacher cannot promote students');
select throws_ok($$select myschool.copy_teaching_assignments('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000002')$$, '42501', null, 'a teacher cannot copy assignments');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');
select throws_ok($$select myschool.promote_class('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000002', 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000002', '{}')$$, '42501', null, 'another school''s admin cannot promote our students');
reset role;
select ok(exists (select 1 from myschool.audit_logs where action = 'promotion.run'), 'promotion is audited');
select ok(exists (select 1 from myschool.audit_logs where action = 'student.status_changed'), 'status changes are audited');

select * from finish();
rollback;
