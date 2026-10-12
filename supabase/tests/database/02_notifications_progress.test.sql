-- pgTAP: notifications, class-specific announcements, class result summary.
-- Run with: supabase db reset && supabase test db   (uses supabase/seed.sql fixtures)
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

-- ===================================================== fixtures (as superuser)
insert into myschool.classes (id, school_id, name)
values ('aaaaaaaa-7000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'JSS 2 A');

insert into myschool.announcements (id, school_id, author_id, title, body, audience, status, class_id) values
 ('aaaaaaaa-a100-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000001', 'JSS 1 trip', 'Bring lunch', 'all', 'published', 'aaaaaaaa-7000-0000-0000-000000000001'),
 ('aaaaaaaa-a100-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000001', 'JSS 2 only',  'Not for JSS 1', 'all', 'published', 'aaaaaaaa-7000-0000-0000-000000000002'),
 ('aaaaaaaa-a100-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000001', 'JSS 1 draft', 'Later', 'all', 'draft', 'aaaaaaaa-7000-0000-0000-000000000001');

-- ===================================================== who gets notified
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-a100-0000-0000-000000000001'), 4,
  'class announcement notifies the 2 students, the parent and the teacher of that class (author skipped)');
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-a100-0000-0000-000000000001'
            and user_id = 'aaaaaaaa-1000-0000-0000-000000000001'), 0, 'the author is not notified about their own announcement');
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-a100-0000-0000-000000000002'), 0,
  'a JSS 2 announcement notifies nobody from JSS 1 (and not the teacher who does not teach JSS 2)');
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-a100-0000-0000-000000000003'), 0,
  'a draft announcement notifies nobody');
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-a100-0000-0000-000000000001'
            and user_id in ('bbbbbbbb-1000-0000-0000-000000000001','bbbbbbbb-2000-0000-0000-000000000001','bbbbbbbb-3000-0000-0000-000000000001')), 0,
  'school B users are never notified about school A announcements');

update myschool.announcements set status = 'published' where id = 'aaaaaaaa-a100-0000-0000-000000000003';
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-a100-0000-0000-000000000003'), 4,
  'publishing a draft notifies the class');
update myschool.announcements set title = 'JSS 1 draft (edited)' where id = 'aaaaaaaa-a100-0000-0000-000000000003';
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-a100-0000-0000-000000000003'), 4,
  'editing a published announcement does not notify again');

-- ===================================================== who can read class announcements
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');   -- Ada, JSS 1 student
select is((select count(*)::int from myschool.announcements where id = 'aaaaaaaa-a100-0000-0000-000000000001'), 1, 'student sees her class announcement');
select is((select count(*)::int from myschool.announcements where id = 'aaaaaaaa-a100-0000-0000-000000000002'), 0, 'student does not see another class announcement');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- Ada's parent
select is((select count(*)::int from myschool.announcements where id = 'aaaaaaaa-a100-0000-0000-000000000001'), 1, 'parent sees the announcement for their child''s class');
select is((select count(*)::int from myschool.announcements where id = 'aaaaaaaa-a100-0000-0000-000000000002'), 0, 'parent does not see other classes');
reset role;
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select is((select count(*)::int from myschool.announcements where id = 'aaaaaaaa-a100-0000-0000-000000000001'), 1, 'assigned teacher sees the class announcement');
select is((select count(*)::int from myschool.announcements where id = 'aaaaaaaa-a100-0000-0000-000000000002'), 0, 'teacher does not see a class they do not teach');
reset role;
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select is((select count(*)::int from myschool.announcements where id in ('aaaaaaaa-a100-0000-0000-000000000001','aaaaaaaa-a100-0000-0000-000000000002')), 2, 'admin sees every class announcement of the school');
select is((select count(*)::int from myschool.notifications where user_id <> 'aaaaaaaa-1000-0000-0000-000000000001'), 0, 'admin cannot read other people''s notifications');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select is((select count(*)::int from myschool.announcements where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'school B admin sees no school A announcements');
reset role;
select tests.act_as('bbbbbbbb-3000-0000-0000-000000000001');   -- student B
select is((select count(*)::int from myschool.announcements where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'school B student sees no school A announcements');
reset role;

-- ===================================================== notification privacy
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');   -- Ada
select ok((select count(*)::int from myschool.notifications) >= 1, 'student has notifications');
select is((select count(*)::int from myschool.notifications where user_id <> 'aaaaaaaa-3000-0000-0000-000000000001'), 0, 'student only sees her own notifications');
select throws_ok($$update myschool.notifications set title = 'hacked'$$, '42501', null, 'only read status can be changed');
select throws_ok($$insert into myschool.notifications (school_id, user_id, kind, title) values ('aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-3000-0000-0000-000000000001','announcement','fake')$$, '42501', null, 'clients cannot create notifications');
select lives_ok($$update myschool.notifications set read_at = now()$$, 'student marks her notifications read');
select is((select count(*)::int from myschool.notifications where read_at is null), 0, 'all of her notifications are now read');
reset role;
select is((select count(*)::int from myschool.notifications where user_id = 'aaaaaaaa-3000-0000-0000-000000000002' and read_at is not null), 0,
  'marking hers read did not touch a classmate''s notifications');

-- ===================================================== class result summary
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select is((select count(*)::int from myschool.class_result_summary), 1, 'teacher sees summaries of approved/published sheets only (not drafts)');
select is((select average from myschool.class_result_summary where sheet_id = 'aaaaaaaa-9000-0000-0000-000000000001'), 60.0::numeric, 'class average is computed correctly');
select is((select highest from myschool.class_result_summary where sheet_id = 'aaaaaaaa-9000-0000-0000-000000000001'), 75.0::numeric, 'highest score is correct');
reset role;
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');   -- student
select is((select count(*)::int from myschool.class_result_summary), 0, 'students cannot read class summaries');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- parent
select is((select count(*)::int from myschool.class_result_summary), 0, 'parents cannot read class summaries');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select is((select count(*)::int from myschool.class_result_summary where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 0, 'school B admin cannot read school A summaries');
select is((select count(*)::int from myschool.class_result_summary), 1, 'school B admin sees their own school''s summary');
reset role;

select * from finish();
rollback;
