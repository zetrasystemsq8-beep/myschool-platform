-- pgTAP: school profile and settings.
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

-- ===================================================== profile
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select lives_ok($$update myschool.schools set motto = 'New motto', contact_phone = '08000000000' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'admin edits the school profile');
select throws_ok($$update myschool.schools set school_code = 'HACK-1' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, '42501', null, 'the School ID can never be changed by a school');
select throws_ok($$update myschool.schools set is_active = false where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, '42501', null, 'a school cannot deactivate itself');
select ok(exists (select 1 from myschool.audit_logs where action = 'school.updated' and school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'the school admin can see the profile change in the audit log');
reset role;
select is((select motto from myschool.schools where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'New motto', 'the change was saved');
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select lives_ok($$update myschool.schools set motto = 'Hijacked' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'another school''s admin update matches nothing');
select is((select count(*)::int from myschool.audit_logs where action = 'school.updated' and school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'and cannot see our audit entries');
reset role;
select is((select motto from myschool.schools where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'New motto', 'school A is untouched');
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select lives_ok($$update myschool.schools set motto = 'Teacher edit' where id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'a teacher update matches nothing');
reset role;
select is((select motto from myschool.schools where id = 'aaaaaaaa-0000-0000-0000-000000000001'), 'New motto', 'teachers cannot edit the school profile');

-- ===================================================== score split
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select throws_ok($$update myschool.school_settings set ca_max = 30 where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, '23514', null, 'test + exam must make 100');
select lives_ok($$update myschool.school_settings set ca_max = 30, exam_max = 70 where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'admin changes the split to 30/70');
reset role;
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');
select lives_ok($$update myschool.school_settings set ca_max = 10, exam_max = 90 where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'a teacher update matches nothing');
reset role;
select is((select ca_max from myschool.school_settings where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 30.00::numeric, 'teachers cannot change the split');

-- ===================================================== grading scale
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select lives_ok($$insert into myschool.grading_scales (school_id, grade, min_score, remark) values ('aaaaaaaa-0000-0000-0000-000000000001', 'A+', 90, 'Distinction')$$, 'admin adds a grade');
select throws_ok($$insert into myschool.grading_scales (school_id, grade, min_score) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Z', 90)$$, '23505', null, 'two grades cannot start at the same score');
select lives_ok($$update myschool.grading_scales set min_score = 85 where school_id = 'aaaaaaaa-0000-0000-0000-000000000001' and grade = 'A+'$$, 'admin edits a grade');
select lives_ok($$delete from myschool.grading_scales where school_id = 'aaaaaaaa-0000-0000-0000-000000000001' and grade = 'A+'$$, 'admin deletes a grade');
reset role;
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');
select throws_ok($$insert into myschool.grading_scales (school_id, grade, min_score) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Q', 95)$$, '42501', null, 'a teacher cannot add grades');
select ok((select count(*)::int from myschool.grading_scales) >= 6, 'a teacher can read the scale');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');
select throws_ok($$insert into myschool.grading_scales (school_id, grade, min_score) values ('aaaaaaaa-0000-0000-0000-000000000001', 'Q', 95)$$, '42501', null, 'another school''s admin cannot add grades here');
reset role;

select * from finish();
rollback;
