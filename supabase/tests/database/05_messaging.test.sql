-- pgTAP: private parent-teacher messaging + moderation.
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

-- ===================================================== who may start a conversation
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- Ada's parent
select lives_ok($$select myschool.start_message_thread('aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-2000-0000-0000-000000000001', 'Homework', 'Hello teacher')$$,
  'a parent starts a conversation with their child''s teacher');
select is((select count(*)::int from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 1, 'the parent sees the conversation');
select throws_ok($$select myschool.start_message_thread('aaaaaaaa-5000-0000-0000-000000000002', 'aaaaaaaa-2000-0000-0000-000000000001', null, 'Hi')$$,
  '42501', null, 'a parent cannot message about a child who is not theirs');
select throws_ok($$select myschool.start_message_thread('aaaaaaaa-5000-0000-0000-000000000001', 'bbbbbbbb-2000-0000-0000-000000000001', null, 'Hi')$$,
  '42501', null, 'a parent cannot message another school''s teacher');
select throws_ok($$select myschool.start_message_thread('aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000001', null, 'Hi')$$,
  '42501', null, 'a parent cannot message someone who is not their child''s teacher');
select throws_ok($$insert into myschool.messages (school_id, thread_id, sender_id, body) values ('aaaaaaaa-0000-0000-0000-000000000001', (select id from myschool.message_threads limit 1), 'aaaaaaaa-4000-0000-0000-000000000001', 'sneaky')$$,
  '42501', null, 'clients cannot write messages directly');
select throws_ok($$update myschool.messages set body = 'edited'$$, '42501', null, 'messages cannot be edited');
select lives_ok($$select myschool.send_message((select thread_id from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 'A second message')$$, 'parent sends another message');
reset role;
select is((select count(*)::int from myschool.notifications where user_id = 'aaaaaaaa-2000-0000-0000-000000000001' and kind = 'message'), 1,
  'the teacher gets one notification per conversation, not one per message');

-- ===================================================== the teacher side
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select is((select count(*)::int from myschool.messages), 2, 'the teacher can read the conversation');
select is((select unread from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 2, 'two unread messages');
select is(myschool.mark_thread_read((select thread_id from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001'))), 2, 'opening the conversation marks messages read');
select is((select unread from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 0, 'no unread left');
select lives_ok($$select myschool.send_message((select thread_id from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 'Hello parent')$$, 'the teacher replies');
select is((select count(*)::int from myschool.my_message_contacts('aaaaaaaa-0000-0000-0000-000000000001')), 1, 'the teacher can write to the parent of the students they teach (only Ada has a linked parent)');
reset role;

-- ===================================================== privacy: nobody else can read it
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select is((select count(*)::int from myschool.messages), 0, 'the administrator cannot read private conversations');
select is((select count(*)::int from myschool.message_threads), 0, 'the administrator cannot list private conversations');
reset role;
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');   -- Ada
select is((select count(*)::int from myschool.messages), 0, 'the student cannot read their parent''s conversation');
select throws_ok($$select myschool.send_message((select id from myschool.message_threads limit 1), 'hi')$$, '42501', null, 'a student cannot send into it');
reset role;
select tests.act_as('bbbbbbbb-2000-0000-0000-000000000001');   -- teacher B
select is((select count(*)::int from myschool.messages), 0, 'another school''s teacher reads nothing');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select is((select count(*)::int from myschool.messages), 0, 'another school''s admin reads nothing');
reset role;

-- ===================================================== reporting
select tests.act_as('aaaaaaaa-2000-0000-0000-000000000001');   -- teacher A
select throws_ok($$select myschool.report_message((select id from myschool.messages where sender_id = 'aaaaaaaa-2000-0000-0000-000000000001' limit 1), 'my own')$$,
  '22023', null, 'you cannot report your own message');
reset role;
select tests.act_as('aaaaaaaa-3000-0000-0000-000000000001');   -- Ada
select throws_ok($$select myschool.report_message((select id from myschool.messages limit 1), 'nosy')$$, '42501', null, 'a non-participant cannot report');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- parent
select lives_ok($$select myschool.report_message((select id from myschool.messages where sender_id = 'aaaaaaaa-2000-0000-0000-000000000001' limit 1), 'This was rude')$$, 'a participant reports a message');
reset role;
select is((select count(*)::int from myschool.notifications where user_id = 'aaaaaaaa-1000-0000-0000-000000000001' and kind = 'message_report'), 1, 'the administrator is told about the report');
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select ok((select count(*)::int from myschool.messages) >= 1, 'after a report the administrator can read that conversation');
select is((select count(*)::int from myschool.list_message_reports('aaaaaaaa-0000-0000-0000-000000000001', 'open')), 1, 'the report is listed');
reset role;
select tests.act_as('bbbbbbbb-1000-0000-0000-000000000001');   -- admin B
select is((select count(*)::int from myschool.messages), 0, 'another school''s admin still reads nothing');
select throws_ok($$select * from myschool.list_message_reports('aaaaaaaa-0000-0000-0000-000000000001', 'open')$$, '42501', null, 'another school''s admin cannot list reports');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');   -- parent
select throws_ok($$select * from myschool.list_message_reports('aaaaaaaa-0000-0000-0000-000000000001', 'open')$$, '42501', null, 'a parent cannot list reports');
select throws_ok($$select myschool.set_messaging_block('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-2000-0000-0000-000000000001', true, 'x')$$, '42501', null, 'a parent cannot mute people');
reset role;

-- ===================================================== muting and switching off
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');   -- admin A
select lives_ok($$select myschool.set_messaging_block('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-4000-0000-0000-000000000001', true, 'misuse')$$, 'admin mutes a parent');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');
select throws_ok($$select myschool.send_message((select thread_id from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 'still here')$$, '42501', null, 'a muted person cannot send');
reset role;
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select lives_ok($$select myschool.set_messaging_block('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-4000-0000-0000-000000000001', false, null)$$, 'admin unmutes');
select lives_ok($$update myschool.school_settings set messaging_enabled = false where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'admin switches messaging off');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');
select throws_ok($$select myschool.send_message((select thread_id from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 'hello?')$$, '55000', null, 'nobody can send while messaging is off');
reset role;
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select lives_ok($$update myschool.school_settings set messaging_enabled = true where school_id = 'aaaaaaaa-0000-0000-0000-000000000001'$$, 'admin switches messaging back on');
reset role;

-- ===================================================== rate limit, then resolve and close
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');
select throws_ok($$select myschool.send_message((select thread_id from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 'spam') from generate_series(1, 40)$$,
  '22023', null, 'sending too many messages in an hour is refused');
reset role;
select tests.act_as('aaaaaaaa-1000-0000-0000-000000000001');
select lives_ok($$select myschool.resolve_message_report((select report_id from myschool.list_message_reports('aaaaaaaa-0000-0000-0000-000000000001', 'open') limit 1), 'Warned the teacher', true)$$, 'admin resolves the report and closes the conversation');
select throws_ok($$select myschool.resolve_message_report((select id from myschool.message_reports limit 1), 'again', false)$$, '55000', null, 'a report can only be resolved once');
reset role;
select tests.act_as('aaaaaaaa-4000-0000-0000-000000000001');
select throws_ok($$select myschool.send_message((select thread_id from myschool.my_message_threads('aaaaaaaa-0000-0000-0000-000000000001')), 'after close')$$, '55000', null, 'nobody can write in a closed conversation');
select throws_ok($$select myschool.start_message_thread('aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-2000-0000-0000-000000000001', null, 'reopen?')$$, '55000', null, 'a closed conversation cannot be restarted');
reset role;
select ok(exists (select 1 from myschool.audit_logs where action = 'message.reported'), 'reporting is audited');
select ok(exists (select 1 from myschool.audit_logs where action = 'message.user_muted'), 'muting is audited');
select ok(exists (select 1 from myschool.audit_logs where action = 'message.report_resolved'), 'resolving is audited');

select * from finish();
rollback;
