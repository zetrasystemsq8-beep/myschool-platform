-- pgTAP security suite. Run with:  supabase db reset && supabase test db
-- Uses the fixtures from supabase/seed.sql. Everything runs in one transaction and is rolled back.
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

-- ===================================================== 1-2, 5-6: students
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');   -- Ada (school A)
select is((select count(*)::int from public.published_results), 1, 'student sees exactly her one PUBLISHED row');
select is((select count(*)::int from public.published_results where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, '1. student cannot read school B results');
select is((select count(*)::int from public.result_items where student_id = 'aaaaaaaa-5000-0000-0000-000000000002'), 0, '2. student cannot read a classmate''s result');
select is((select count(*)::int from public.result_items where sheet_id = 'aaaaaaaa-9000-0000-0000-000000000002'), 0, '5. unpublished (draft) results are invisible to the student');
select is((select count(*)::int from public.result_sheets where status <> 'published'), 0, 'student cannot see non-published sheets');
select is((select count(*)::int from public.students), 1, 'student sees only her own student row');
select is((select count(*)::int from public.student_private), 1, 'student can read own private record');
select is((select count(*)::int from public.audit_logs), 0, 'student cannot read audit logs');
select lives_ok($$update public.result_items set exam_score = 60 where id = 'aaaaaaaa-9100-0000-0000-000000000001'$$, 'student update runs but matches 0 rows');
select throws_ok($$insert into public.result_items (school_id, sheet_id, student_id, ca_score, exam_score) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-9000-0000-0000-000000000002','aaaaaaaa-5000-0000-0000-000000000001',1,1)$$, '42501', null, 'student cannot insert results');
select throws_ok($$select public.publish_result_sheet('aaaaaaaa-9000-0000-0000-000000000002')$$, '42501', null, 'student cannot publish');
select throws_ok($$update public.profiles set is_platform_admin = true where id = 'aaaaaaaa-3000-0000-0000-000000000001'$$, '42501', null, 'user cannot make themselves platform admin');
select throws_ok($$update public.school_members set role = 'school_admin' where user_id = 'aaaaaaaa-3000-0000-0000-000000000001'$$, '42501', null, 'user cannot change own role');
reset role;
select is((select exam_score from public.result_items where id = 'aaaaaaaa-9100-0000-0000-000000000001'), 45::numeric, 'score unchanged after student update attempt');

-- ===================================================== 6: only the correct student / parent
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000002');   -- Bayo
select is((select count(*)::int from public.published_results where student_id = 'aaaaaaaa-5000-0000-0000-000000000001'), 0, '6. Bayo cannot see Ada''s published result');
select is((select count(*)::int from public.published_results where student_id = 'aaaaaaaa-5000-0000-0000-000000000002'), 1, '6. Bayo sees his own published result');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- Ada's parent
select is((select count(*)::int from public.published_results where student_id = 'aaaaaaaa-5000-0000-0000-000000000001'), 1, 'parent sees child''s published result');
select is((select count(*)::int from public.published_results where student_id = 'aaaaaaaa-5000-0000-0000-000000000002'), 0, 'parent cannot see another child''s result');
select is((select count(*)::int from public.result_items where sheet_id = 'aaaaaaaa-9000-0000-0000-000000000002'), 0, 'parent cannot see draft results');
reset role;
select tests.act_as('bbbbbbbb-3000-0000-0000-000000000001');   -- Chika (school B)
select is((select count(*)::int from public.published_results where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, '1. school B student cannot read school A results');
select is((select count(*)::int from public.published_results), 1, 'school B student sees only own result');
reset role;

-- ===================================================== 3: teachers
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select is((select count(*)::int from public.students where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, '3. teacher A cannot read school B students');
select is((select count(*)::int from public.students), 2, 'teacher A sees students of classes they teach');
select is((select count(*)::int from public.student_private), 0, 'teacher cannot read sensitive student data');
select throws_ok($$insert into public.students (school_id, admission_number, first_name, last_name) values ('bbbbbbbb-0000-0000-0000-000000000001','X1','No','Way')$$, '42501', null, '3. teacher cannot create students in school B');
select throws_ok($$insert into public.students (school_id, admission_number, first_name, last_name) values ('aaaaaaaa-0000-0000-0000-000000000001','X2','No','Way')$$, '42501', null, 'teacher cannot create students even in own school');
select throws_ok($$insert into public.result_sheets (school_id, term_id, class_id, subject_id, created_by) values ('bbbbbbbb-0000-0000-0000-000000000001','bbbbbbbb-6100-0000-0000-000000000001','bbbbbbbb-7000-0000-0000-000000000001','bbbbbbbb-7100-0000-0000-000000000001','aaaaaaaa-2000-0000-0000-000000000001')$$, '42501', null, 'teacher cannot open a sheet in school B');
select lives_ok($$update public.students set first_name = 'Hacked' where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'$$, 'cross-school update runs but matches 0 rows');
select throws_ok($$select public.approve_result_sheet('aaaaaaaa-9000-0000-0000-000000000002')$$, '42501', null, 'teacher cannot approve');
select throws_ok($$update public.result_sheets set status = 'published' where id = 'aaaaaaaa-9000-0000-0000-000000000002'$$, '42501', null, 'nobody can set sheet status directly');
select throws_ok($$update public.result_items set exam_score = 99 where id = 'aaaaaaaa-9100-0000-0000-000000000003'$$, '23514', null, 'score above exam maximum is rejected');
select lives_ok($$update public.result_items set exam_score = 41 where id = 'aaaaaaaa-9100-0000-0000-000000000003'$$, 'teacher edits draft score');
select lives_ok($$select public.submit_result_sheet('aaaaaaaa-9000-0000-0000-000000000002')$$, 'teacher submits complete sheet');
select lives_ok($$update public.result_items set exam_score = 5 where id = 'aaaaaaaa-9100-0000-0000-000000000003'$$, 'edit after submit runs but matches 0 rows');
select throws_ok($$select public.submit_result_sheet('aaaaaaaa-9000-0000-0000-000000000001')$$, '55000', null, 'cannot submit an already published sheet');
reset role;
select is((select exam_score from public.result_items where id = 'aaaaaaaa-9100-0000-0000-000000000003'), 41::numeric, 'teacher cannot edit items after submission');
select is((select grade from public.result_items where id = 'aaaaaaaa-9100-0000-0000-000000000003'), 'B', 'grade is computed by the database');
select is((select first_name from public.students where id = 'bbbbbbbb-5000-0000-0000-000000000001'), 'Chika', 'school B student untouched');

-- ===================================================== 4: school admins + workflow
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select is((select count(*)::int from public.schools), 1, '4. admin sees only own school');
select is((select count(*)::int from public.students where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, '4. admin A cannot read school B students');
select is((select count(*)::int from public.result_sheets where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, '4. admin A cannot read school B sheets');
select is((select count(*)::int from public.classes where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'admin A cannot read school B classes');
select is((select count(*)::int from public.school_members where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'admin A cannot read school B staff');
select is((select count(*)::int from public.announcements where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'admin A cannot read school B announcements');
select is((select count(*)::int from public.audit_logs where school_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 0, 'admin A cannot read school B audit logs');
select ok((select count(*)::int from public.audit_logs where school_id = 'aaaaaaaa-0000-0000-0000-000000000001') > 0, 'admin A can read own audit logs');
select throws_ok($$insert into public.classes (school_id, name) values ('bbbbbbbb-0000-0000-0000-000000000001','Hack')$$, '42501', null, '4. admin A cannot create classes in school B');
select throws_ok($$update public.schools set school_code = 'HACK-1' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, '42501', null, 'admin cannot change school_code');
select throws_ok($$select public.create_school('NEW-1','New School')$$, '42501', null, 'school admin cannot create schools');
select throws_ok($$delete from public.audit_logs$$, '42501', null, 'audit logs cannot be deleted by clients');
select lives_ok($$select public.approve_result_sheet('aaaaaaaa-9000-0000-0000-000000000002')$$, 'admin approves submitted sheet');
select is((select count(*)::int from public.published_results where subject_code = 'ENG'), 0, 'approved-but-unpublished data is still not in the published view');
select lives_ok($$select public.publish_result_sheet('aaaaaaaa-9000-0000-0000-000000000002')$$, 'admin publishes approved sheet');
select throws_ok($$select public.unpublish_result_sheet('aaaaaaaa-9000-0000-0000-000000000002', '')$$, '22023', null, 'unpublish requires a reason');
reset role;
select ok(exists (select 1 from public.audit_logs where action = 'result_sheet.published' and entity_id = 'aaaaaaaa-9000-0000-0000-000000000002'), 'publish is audited');
select ok(exists (select 1 from public.audit_logs where action = 'result_sheet.submitted' and actor_id = 'aaaaaaaa-2000-0000-0000-000000000001'), 'submission is audited with actor');
select ok(exists (select 1 from public.audit_logs where action = 'result_item.updated' and entity_id = 'aaaaaaaa-9100-0000-0000-000000000003'), 'score change is audited');
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');
select is((select count(*)::int from public.published_results), 2, '6. after publishing, the student sees the new result');
reset role;

-- ===================================================== database-level integrity (RLS bypassed)
select throws_ok($$insert into public.enrollments (school_id, student_id, class_id, session_id) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-5000-0000-0000-000000000001','bbbbbbbb-7000-0000-0000-000000000001','bbbbbbbb-6000-0000-0000-000000000001')$$, '23503', null, 'composite FK blocks cross-school enrollment');
select throws_ok($$insert into public.parent_students (school_id, parent_user_id, student_id) values ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-4000-0000-0000-000000000001','bbbbbbbb-5000-0000-0000-000000000001')$$, '23514', null, 'cannot link a parent from another school');
select throws_ok($$update public.audit_logs set action = 'tampered'$$, '42501', null, 'audit log is append-only');
select throws_ok($$update public.result_sheets set status = 'draft' where id = 'aaaaaaaa-9000-0000-0000-000000000001'$$, '42501', null, 'status guard trigger blocks direct changes even for superuser');
select throws_ok($$update public.students set school_id = 'bbbbbbbb-0000-0000-0000-000000000001' where id = 'aaaaaaaa-5000-0000-0000-000000000002'$$, '23514', null, 'a row can never change school');

-- ===================================================== 7: public discovery
select tests.act_anon();
select is((select count(*)::int from public.search_schools('Demo')), 2, 'anon can search schools by name');
select is((select count(*)::int from public.search_schools('demo-a')), 1, 'anon can search by School ID');
select is((select count(*)::int from public.search_schools('a')), 0, 'too-short query returns nothing');
select is((select count(*)::int from public.search_schools('%%')), 0, 'LIKE wildcards are escaped');
select is(pg_get_function_result('public.search_schools(text,integer)'::regprocedure),
  'TABLE(id uuid, school_code text, name text, motto text, logo_path text, city text, state text)', '7. search exposes only public columns');
select throws_ok($$select * from public.schools$$, '42501', null, '7. anon cannot read the schools table');
select throws_ok($$select * from public.students$$, '42501', null, 'anon cannot read students');
select throws_ok($$select * from public.result_items$$, '42501', null, 'anon cannot read results');
select throws_ok($$select * from public.published_results$$, '42501', null, 'anon cannot read the results view');
select throws_ok($$select public.create_school('X-1','X')$$, '42501', null, 'anon cannot call create_school');
select is((select count(*)::int from public.get_public_school('DEMO-B')), 1, 'public profile available by code');
reset role;
update public.schools set is_listed = false where id = 'bbbbbbbb-0000-0000-0000-000000000001';
select tests.act_anon();
select is((select count(*)::int from public.search_schools('Demo')), 1, 'unlisted schools disappear from search');
reset role;

-- ===================================================== announcements
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');
select is((select count(*)::int from public.announcements), 1, 'student sees only published announcements for students/all');
reset role;
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');
select is((select count(*)::int from public.announcements), 2, 'teacher also sees staff announcements, never drafts');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');
select is((select count(*)::int from public.announcements where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'school B admin cannot read school A announcements');
reset role;

select * from finish();
rollback;
