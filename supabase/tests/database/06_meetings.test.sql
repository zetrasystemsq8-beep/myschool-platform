-- pgTAP: meetings, RSVP and notifications.
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

-- ===================================================== admin schedules
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select lives_ok($$insert into myschool.meetings (id, school_id, title, starts_at, ends_at, class_id) values ('aaaaaaaa-c000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','PTM', now() + interval '3 days', now() + interval '3 days 1 hour','aaaaaaaa-7000-0000-0000-000000000001')$$, 'admin schedules a class meeting');
select lives_ok($$insert into myschool.meetings (id, school_id, title, starts_at, ends_at) values ('aaaaaaaa-c000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','Open day', now() + interval '10 days', now() + interval '10 days 2 hours')$$, 'admin schedules a school-wide meeting');
select throws_ok($$insert into myschool.meetings (school_id, title, starts_at, ends_at) values ('aaaaaaaa-0000-0000-0000-000000000001','Backwards', now() + interval '3 days', now() + interval '2 days')$$, '23514', null, 'a meeting cannot end before it starts');
reset role;

select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-c000-0000-0000-000000000001' and user_id = 'aaaaaaaa-4000-0000-0000-000000000001'), 1, 'the class''s parent is notified');
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-c000-0000-0000-000000000001' and user_id = 'aaaaaaaa-2000-0000-0000-000000000001'), 1, 'the teacher of that class is notified');
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-c000-0000-0000-000000000001' and user_id in ('aaaaaaaa-3000-0000-0000-000000000001','aaaaaaaa-1000-0000-0000-000000000001','bbbbbbbb-1000-0000-0000-000000000001','bbbbbbbb-2000-0000-0000-000000000001')), 0, 'students, the creator and other schools are not notified');

select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select lives_ok($$update myschool.meetings set location = 'School hall' where id = 'aaaaaaaa-c000-0000-0000-000000000001'$$, 'admin edits the meeting');
reset role;
select is((select count(*)::int from myschool.notifications where entity_id = 'aaaaaaaa-c000-0000-0000-000000000001' and user_id = 'aaaaaaaa-4000-0000-0000-000000000001'), 1, 'an update replaces the unread notification instead of adding another');
select is((select title from myschool.notifications where entity_id = 'aaaaaaaa-c000-0000-0000-000000000001' and user_id = 'aaaaaaaa-4000-0000-0000-000000000001'), 'Meeting updated: PTM', 'and says the meeting was updated');

-- ===================================================== who can see meetings
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- parent
select is((select count(*)::int from myschool.meetings), 2, 'the parent sees the class meeting and the school-wide one');
select lives_ok($$select myschool.respond_to_meeting('aaaaaaaa-c000-0000-0000-000000000001', 'attending', null)$$, 'the parent confirms attendance');
select lives_ok($$select myschool.respond_to_meeting('aaaaaaaa-c000-0000-0000-000000000001', 'not_attending', 'sorry')$$, 'and can change their mind');
select is((select count(*)::int from myschool.meeting_rsvps), 1, 'still a single answer');
select throws_ok($$insert into myschool.meeting_rsvps (meeting_id, school_id, parent_user_id, response) values ('aaaaaaaa-c000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','aaaaaaaa-4000-0000-0000-000000000001','attending')$$, '42501', null, 'answers cannot be written directly');
select throws_ok($$select * from myschool.meeting_rsvp_report('aaaaaaaa-c000-0000-0000-000000000001')$$, '42501', null, 'a parent cannot see everyone''s answers');
select throws_ok($$insert into myschool.meetings (school_id, title, starts_at, ends_at) values ('aaaaaaaa-0000-0000-0000-000000000001','Mine', now() + interval '1 day', now() + interval '2 days')$$, '42501', null, 'a parent cannot schedule meetings');
reset role;
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select is((select count(*)::int from myschool.meetings), 2, 'the teacher sees the meetings that concern them');
select throws_ok($$select myschool.respond_to_meeting('aaaaaaaa-c000-0000-0000-000000000001', 'attending', null)$$, '42501', null, 'a teacher cannot RSVP as a parent');
select throws_ok($$insert into myschool.meetings (school_id, title, starts_at, ends_at) values ('aaaaaaaa-0000-0000-0000-000000000001','Mine', now() + interval '1 day', now() + interval '2 days')$$, '42501', null, 'a teacher cannot schedule meetings');
reset role;
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');   -- Ada
select is((select count(*)::int from myschool.meetings), 0, 'students do not see parent-teacher meetings');
select throws_ok($$select myschool.respond_to_meeting('aaaaaaaa-c000-0000-0000-000000000001', 'attending', null)$$, '42501', null, 'a student cannot RSVP');
reset role;
select tests.act_as('bbbbbbbb-2000-0000-0000-000000000001');   -- teacher B
select is((select count(*)::int from myschool.meetings), 0, 'another school''s teacher sees nothing');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select is((select count(*)::int from myschool.meetings), 0, 'another school''s admin sees nothing');
select throws_ok($$insert into myschool.meetings (school_id, title, starts_at, ends_at) values ('aaaaaaaa-0000-0000-0000-000000000001','Hijack', now() + interval '1 day', now() + interval '2 days')$$, '42501', null, 'another school''s admin cannot schedule here');
select lives_ok($$update myschool.meetings set title = 'Hacked'$$, 'a cross-school update matches nothing');
select throws_ok($$select * from myschool.meeting_rsvp_report('aaaaaaaa-c000-0000-0000-000000000001')$$, '42501', null, 'another school''s admin cannot read answers');
reset role;
select is((select title from myschool.meetings where id = 'aaaaaaaa-c000-0000-0000-000000000001'), 'PTM', 'the title is untouched');

-- ===================================================== admin sees answers, cancel, past meetings
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select is((select response from myschool.meeting_rsvp_report('aaaaaaaa-c000-0000-0000-000000000001')), 'not_attending', 'admin sees the parent''s latest answer');
select is((select response from myschool.meeting_rsvp_report('aaaaaaaa-c000-0000-0000-000000000002')), 'no_response', 'and who has not answered');
select lives_ok($$update myschool.meetings set status = 'cancelled' where id = 'aaaaaaaa-c000-0000-0000-000000000001'$$, 'admin cancels the meeting');
reset role;
select is((select title from myschool.notifications where entity_id = 'aaaaaaaa-c000-0000-0000-000000000001' and user_id = 'aaaaaaaa-4000-0000-0000-000000000001'), 'Meeting cancelled: PTM', 'parents are told it was cancelled');
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');
select throws_ok($$select myschool.respond_to_meeting('aaaaaaaa-c000-0000-0000-000000000001', 'attending', null)$$, '55000', null, 'nobody can RSVP to a cancelled meeting');
reset role;
insert into myschool.meetings (id, school_id, title, starts_at, ends_at)
values ('aaaaaaaa-c000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'Old meeting', now() - interval '2 days', now() - interval '2 days' + interval '1 hour');
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');
select throws_ok($$select myschool.respond_to_meeting('aaaaaaaa-c000-0000-0000-000000000003', 'attending', null)$$, '55000', null, 'nobody can RSVP to a meeting that is over');
reset role;
select ok(exists (select 1 from myschool.audit_logs where action = 'meeting.created'), 'scheduling a meeting is audited');

select * from finish();
rollback;
