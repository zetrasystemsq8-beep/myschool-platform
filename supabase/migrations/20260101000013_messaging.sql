-- 13: private parent-teacher messaging with moderation.
-- Only a parent and a teacher of their child can talk. Admins do NOT read private conversations; they can
-- read a conversation only after someone reports it, and can mute people or switch messaging off.
alter table myschool.school_settings add column messaging_enabled boolean not null default true;
grant update (messaging_enabled) on myschool.school_settings to authenticated;  -- existing admin-only update policy applies

-- ---------------------------------------------------------------- eligibility helpers
create or replace function ms_private.active_member(p_school uuid, p_user uuid, p_role myschool.school_role)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from myschool.school_members m
                 where m.school_id = p_school and m.user_id = p_user and m.role = p_role and m.status = 'active')
$$;

create or replace function ms_private.parent_of_student(p_school uuid, p_parent uuid, p_student uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from myschool.parent_students ps
                 where ps.school_id = p_school and ps.parent_user_id = p_parent and ps.student_id = p_student)
$$;

-- the teacher teaches the student's class in the CURRENT school year
create or replace function ms_private.teacher_teaches_student(p_school uuid, p_teacher uuid, p_student uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from myschool.enrollments e
    join myschool.academic_sessions s on s.id = e.session_id and s.is_current
    join myschool.teaching_assignments ta
      on ta.class_id = e.class_id and ta.session_id = e.session_id and ta.school_id = e.school_id
    where e.school_id = p_school and e.student_id = p_student and e.status <> 'withdrawn'
      and ta.teacher_user_id = p_teacher)
$$;

create or replace function ms_private.can_converse(p_school uuid, p_parent uuid, p_teacher uuid, p_student uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select ms_private.active_member(p_school, p_parent, 'parent')
     and ms_private.active_member(p_school, p_teacher, 'teacher')
     and ms_private.parent_of_student(p_school, p_parent, p_student)
     and ms_private.teacher_teaches_student(p_school, p_teacher, p_student)
$$;

-- ---------------------------------------------------------------- tables
create table myschool.message_threads (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null,
  student_id      uuid not null,
  parent_user_id  uuid not null,
  teacher_user_id uuid not null,
  subject         text check (subject is null or char_length(subject) <= 120),
  status          text not null default 'open' check (status in ('open', 'closed')),
  created_by      uuid references myschool.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now(),
  closed_at       timestamptz,
  unique (student_id, parent_user_id, teacher_user_id),
  unique (id, school_id),
  foreign key (student_id, school_id) references myschool.students (id, school_id) on delete cascade,
  foreign key (school_id, parent_user_id) references myschool.school_members (school_id, user_id) on delete cascade,
  foreign key (school_id, teacher_user_id) references myschool.school_members (school_id, user_id) on delete cascade
);
create index message_threads_parent_idx on myschool.message_threads (parent_user_id, last_message_at desc);
create index message_threads_teacher_idx on myschool.message_threads (teacher_user_id, last_message_at desc);
create trigger threads_parent_role before insert on myschool.message_threads
  for each row execute function ms_private.assert_member_role('parent_user_id', 'parent');
create trigger threads_teacher_role before insert on myschool.message_threads
  for each row execute function ms_private.assert_member_role('teacher_user_id', 'teacher');

create table myschool.messages (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null,
  thread_id  uuid not null,
  sender_id  uuid not null references myschool.profiles (id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at    timestamptz,
  foreign key (thread_id, school_id) references myschool.message_threads (id, school_id) on delete cascade
);
create index messages_thread_idx on myschool.messages (thread_id, created_at);
create index messages_sender_recent_idx on myschool.messages (sender_id, created_at desc);

create table myschool.message_reports (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null,
  thread_id       uuid not null,
  message_id      uuid not null references myschool.messages (id) on delete cascade,
  reported_by     uuid not null references myschool.profiles (id) on delete cascade,
  reason          text not null check (char_length(reason) between 3 and 500),
  status          text not null default 'open' check (status in ('open', 'resolved')),
  created_at      timestamptz not null default now(),
  resolved_by     uuid references myschool.profiles (id) on delete set null,
  resolved_at     timestamptz,
  resolution_note text,
  unique (message_id, reported_by),
  foreign key (thread_id, school_id) references myschool.message_threads (id, school_id) on delete cascade
);
create index message_reports_open_idx on myschool.message_reports (school_id, status);

create table myschool.message_blocks (
  school_id  uuid not null,
  user_id    uuid not null references myschool.profiles (id) on delete cascade,
  blocked_by uuid references myschool.profiles (id) on delete set null,
  reason     text,
  created_at timestamptz not null default now(),
  primary key (school_id, user_id),
  foreign key (school_id, user_id) references myschool.school_members (school_id, user_id) on delete cascade
);

-- ---------------------------------------------------------------- read access (no direct writes at all)
create or replace function ms_private.is_thread_participant(p_thread uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from myschool.message_threads t
                 where t.id = p_thread and (t.parent_user_id = auth.uid() or t.teacher_user_id = auth.uid())
                   and ms_private.is_member(t.school_id))
$$;
create or replace function ms_private.thread_is_reported(p_thread uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from myschool.message_reports r where r.thread_id = p_thread)
$$;

alter table myschool.message_threads enable row level security;
alter table myschool.messages        enable row level security;
alter table myschool.message_reports enable row level security;
alter table myschool.message_blocks  enable row level security;

create policy threads_select on myschool.message_threads for select to authenticated
  using (ms_private.is_thread_participant(id)
         or (ms_private.is_school_admin(school_id) and ms_private.thread_is_reported(id)));
create policy messages_select on myschool.messages for select to authenticated
  using (ms_private.is_thread_participant(thread_id)
         or (ms_private.is_school_admin(school_id) and ms_private.thread_is_reported(thread_id)));
create policy reports_select on myschool.message_reports for select to authenticated
  using (reported_by = (select auth.uid()) or ms_private.is_school_admin(school_id));
create policy blocks_select on myschool.message_blocks for select to authenticated
  using (user_id = (select auth.uid()) or ms_private.is_school_admin(school_id));

-- ---------------------------------------------------------------- notification helper (one per conversation until read)
create or replace function ms_private.notify_new_message(p_school uuid, p_to uuid, p_thread uuid, p_from_name text, p_student_name text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update myschool.notifications
     set title = 'New message from ' || p_from_name, body = 'About ' || p_student_name, created_at = now()
   where user_id = p_to and kind = 'message' and entity_id = p_thread and read_at is null;
  if not found then
    insert into myschool.notifications (school_id, user_id, kind, title, body, entity_type, entity_id)
    values (p_school, p_to, 'message', 'New message from ' || p_from_name, 'About ' || p_student_name, 'message_thread', p_thread);
  end if;
end $$;

-- ---------------------------------------------------------------- RPCs
create or replace function myschool.start_message_thread(p_student uuid, p_other uuid, p_subject text, p_body text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); v_school uuid; v_parent uuid; v_teacher uuid; v_thread uuid; v_status text;
  v_body text := trim(coalesce(p_body, '')); v_student_name text; v_my_name text;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select school_id, first_name into v_school, v_student_name from myschool.students where id = p_student;
  if v_school is null then raise exception 'student not found' using errcode = 'P0002'; end if;
  if not coalesce((select messaging_enabled from myschool.school_settings where school_id = v_school), true) then
    raise exception 'Messaging is switched off by your school.' using errcode = '55000';
  end if;
  if exists (select 1 from myschool.message_blocks b where b.school_id = v_school and b.user_id = v_uid) then
    raise exception 'You cannot send messages right now. Please contact your school.' using errcode = '42501';
  end if;
  if ms_private.active_member(v_school, v_uid, 'parent') then
    v_parent := v_uid; v_teacher := p_other;
  elsif ms_private.active_member(v_school, v_uid, 'teacher') then
    v_teacher := v_uid; v_parent := p_other;
  else
    raise exception 'Only parents and teachers can send messages.' using errcode = '42501';
  end if;
  if not ms_private.can_converse(v_school, v_parent, v_teacher, p_student) then
    raise exception 'You can only message a parent and teacher of the same student.' using errcode = '42501';
  end if;
  if char_length(v_body) not between 1 and 2000 then
    raise exception 'Write a message between 1 and 2000 characters.' using errcode = '22023';
  end if;

  select id, status into v_thread, v_status from myschool.message_threads
   where student_id = p_student and parent_user_id = v_parent and teacher_user_id = v_teacher;
  if v_thread is not null and v_status = 'closed' then
    raise exception 'This conversation was closed by the school.' using errcode = '55000';
  end if;
  if v_thread is null then
    insert into myschool.message_threads (school_id, student_id, parent_user_id, teacher_user_id, subject, created_by)
    values (v_school, p_student, v_parent, v_teacher, nullif(trim(coalesce(p_subject, '')), ''), v_uid)
    returning id into v_thread;
    perform ms_private.write_audit(v_school, 'message.thread_started', 'message_thread', v_thread,
                                   jsonb_build_object('student_id', p_student));
  end if;
  insert into myschool.messages (school_id, thread_id, sender_id, body) values (v_school, v_thread, v_uid, v_body);
  update myschool.message_threads set last_message_at = now() where id = v_thread;
  select coalesce(nullif(trim(full_name), ''), 'someone') into v_my_name from myschool.profiles where id = v_uid;
  perform ms_private.notify_new_message(v_school, case when v_uid = v_parent then v_teacher else v_parent end,
                                        v_thread, coalesce(v_my_name, 'someone'), v_student_name);
  return v_thread;
end $$;

create or replace function myschool.send_message(p_thread uuid, p_body text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid(); t myschool.message_threads; v_id uuid; v_body text := trim(coalesce(p_body, ''));
  v_student_name text; v_my_name text;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into t from myschool.message_threads where id = p_thread;
  if t.id is null or v_uid not in (t.parent_user_id, t.teacher_user_id) or not ms_private.is_member(t.school_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not coalesce((select messaging_enabled from myschool.school_settings where school_id = t.school_id), true) then
    raise exception 'Messaging is switched off by your school.' using errcode = '55000';
  end if;
  if exists (select 1 from myschool.message_blocks b where b.school_id = t.school_id and b.user_id = v_uid) then
    raise exception 'You cannot send messages right now. Please contact your school.' using errcode = '42501';
  end if;
  if t.status = 'closed' then
    raise exception 'This conversation was closed by the school.' using errcode = '55000';
  end if;
  if not ms_private.can_converse(t.school_id, t.parent_user_id, t.teacher_user_id, t.student_id) then
    raise exception 'This conversation can no longer continue (the teacher no longer teaches this student).' using errcode = '55000';
  end if;
  if char_length(v_body) not between 1 and 2000 then
    raise exception 'Write a message between 1 and 2000 characters.' using errcode = '22023';
  end if;
  if (select count(*) from myschool.messages m where m.sender_id = v_uid and m.created_at > now() - interval '1 hour') >= 30 then
    raise exception 'You are sending messages too fast. Please wait a little.' using errcode = '22023';
  end if;
  insert into myschool.messages (school_id, thread_id, sender_id, body) values (t.school_id, t.id, v_uid, v_body)
  returning id into v_id;
  update myschool.message_threads set last_message_at = now() where id = t.id;
  select first_name into v_student_name from myschool.students where id = t.student_id;
  select coalesce(nullif(trim(full_name), ''), 'someone') into v_my_name from myschool.profiles where id = v_uid;
  perform ms_private.notify_new_message(t.school_id, case when v_uid = t.parent_user_id then t.teacher_user_id else t.parent_user_id end,
                                        t.id, coalesce(v_my_name, 'someone'), v_student_name);
  return v_id;
end $$;

create or replace function myschool.mark_thread_read(p_thread uuid) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_n integer;
begin
  if not ms_private.is_thread_participant(p_thread) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  update myschool.messages set read_at = now()
   where thread_id = p_thread and sender_id <> auth.uid() and read_at is null;
  get diagnostics v_n = row_count;
  update myschool.notifications set read_at = now()
   where user_id = auth.uid() and kind = 'message' and entity_id = p_thread and read_at is null;
  return v_n;
end $$;

create or replace function myschool.report_message(p_message uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare m myschool.messages; v_id uuid; v_admin uuid;
begin
  select * into m from myschool.messages where id = p_message;
  if m.id is null or not ms_private.is_thread_participant(m.thread_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if m.sender_id = auth.uid() then
    raise exception 'You cannot report your own message.' using errcode = '22023';
  end if;
  if char_length(trim(coalesce(p_reason, ''))) < 3 then
    raise exception 'Please say what is wrong (at least a few words).' using errcode = '22023';
  end if;
  insert into myschool.message_reports (school_id, thread_id, message_id, reported_by, reason)
  values (m.school_id, m.thread_id, m.id, auth.uid(), trim(p_reason))
  on conflict (message_id, reported_by) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from myschool.message_reports where message_id = m.id and reported_by = auth.uid();
    return v_id;
  end if;
  perform ms_private.write_audit(m.school_id, 'message.reported', 'message_report', v_id, jsonb_build_object('thread_id', m.thread_id));
  for v_admin in select user_id from myschool.school_members where school_id = m.school_id and role = 'school_admin' and status = 'active' loop
    insert into myschool.notifications (school_id, user_id, kind, title, body, entity_type, entity_id)
    values (m.school_id, v_admin, 'message_report', 'A message was reported', 'Open Messages under More to review it.', 'message_report', v_id);
  end loop;
  return v_id;
end $$;

create or replace function myschool.resolve_message_report(p_report uuid, p_note text, p_close_thread boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare r myschool.message_reports;
begin
  select * into r from myschool.message_reports where id = p_report;
  if r.id is null or not ms_private.is_school_admin(r.school_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if r.status = 'resolved' then
    raise exception 'This report is already resolved.' using errcode = '55000';
  end if;
  update myschool.message_reports set status = 'resolved', resolved_by = auth.uid(), resolved_at = now(),
         resolution_note = nullif(trim(coalesce(p_note, '')), '') where id = p_report;
  if p_close_thread then
    update myschool.message_threads set status = 'closed', closed_at = now() where id = r.thread_id;
  end if;
  perform ms_private.write_audit(r.school_id, 'message.report_resolved', 'message_report', r.id,
                                 jsonb_build_object('closed_thread', p_close_thread));
end $$;

create or replace function myschool.set_messaging_block(p_school uuid, p_user uuid, p_blocked boolean, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not ms_private.is_school_admin(p_school) then raise exception 'not allowed' using errcode = '42501'; end if;
  if p_blocked then
    insert into myschool.message_blocks (school_id, user_id, blocked_by, reason)
    values (p_school, p_user, auth.uid(), nullif(trim(coalesce(p_reason, '')), ''))
    on conflict (school_id, user_id) do update set reason = excluded.reason, blocked_by = auth.uid();
  else
    delete from myschool.message_blocks where school_id = p_school and user_id = p_user;
  end if;
  perform ms_private.write_audit(p_school, case when p_blocked then 'message.user_muted' else 'message.user_unmuted' end,
                                 'profile', p_user, jsonb_build_object('reason', p_reason));
end $$;

-- ---------------------------------------------------------------- lists (names come from here, so nobody needs to read profiles)
create or replace function myschool.my_message_threads(p_school uuid)
returns table (thread_id uuid, student_id uuid, student_name text, other_user_id uuid, other_name text,
               other_role text, subject text, status text, last_message_at timestamptz, last_body text, unread integer)
language sql stable security definer set search_path = '' as $$
  select t.id, t.student_id, trim(st.first_name || ' ' || st.last_name),
         case when t.parent_user_id = auth.uid() then t.teacher_user_id else t.parent_user_id end,
         coalesce(nullif(trim(op.full_name), ''), case when t.parent_user_id = auth.uid() then 'Teacher' else 'Parent' end),
         case when t.parent_user_id = auth.uid() then 'teacher' else 'parent' end,
         t.subject, t.status, t.last_message_at,
         (select left(m.body, 120) from myschool.messages m where m.thread_id = t.id order by m.created_at desc limit 1),
         (select count(*)::int from myschool.messages m where m.thread_id = t.id and m.sender_id <> auth.uid() and m.read_at is null)
    from myschool.message_threads t
    join myschool.students st on st.id = t.student_id
    left join myschool.profiles op on op.id = case when t.parent_user_id = auth.uid() then t.teacher_user_id else t.parent_user_id end
   where t.school_id = p_school and (t.parent_user_id = auth.uid() or t.teacher_user_id = auth.uid())
     and ms_private.is_member(p_school)
   order by t.last_message_at desc
$$;

-- who the caller may start a conversation with: a parent sees their children's teachers; a teacher sees parents of students they teach
create or replace function myschool.my_message_contacts(p_school uuid)
returns table (student_id uuid, student_name text, other_user_id uuid, other_name text, other_role text, detail text)
language sql stable security definer set search_path = '' as $$
  select ps.student_id, trim(st.first_name || ' ' || st.last_name), ta.teacher_user_id,
         coalesce(nullif(trim(p.full_name), ''), 'Teacher'), 'teacher',
         string_agg(distinct sub.name, ', ' order by sub.name)
    from myschool.parent_students ps
    join myschool.students st on st.id = ps.student_id
    join myschool.enrollments e on e.student_id = ps.student_id and e.status <> 'withdrawn'
    join myschool.academic_sessions s on s.id = e.session_id and s.is_current
    join myschool.teaching_assignments ta on ta.class_id = e.class_id and ta.session_id = e.session_id and ta.school_id = e.school_id
    join myschool.subjects sub on sub.id = ta.subject_id
    left join myschool.profiles p on p.id = ta.teacher_user_id
   where ps.school_id = p_school and ps.parent_user_id = auth.uid()
     and ms_private.active_member(p_school, auth.uid(), 'parent')
     and ms_private.active_member(p_school, ta.teacher_user_id, 'teacher')
   group by ps.student_id, st.first_name, st.last_name, ta.teacher_user_id, p.full_name
  union all
  select ps.student_id, trim(st.first_name || ' ' || st.last_name), ps.parent_user_id,
         coalesce(nullif(trim(p.full_name), ''), 'Parent'), 'parent', 'Parent of ' || st.first_name
    from myschool.teaching_assignments ta
    join myschool.enrollments e on e.class_id = ta.class_id and e.session_id = ta.session_id and e.status <> 'withdrawn'
    join myschool.academic_sessions s on s.id = e.session_id and s.is_current
    join myschool.parent_students ps on ps.student_id = e.student_id and ps.school_id = ta.school_id
    join myschool.students st on st.id = e.student_id
    left join myschool.profiles p on p.id = ps.parent_user_id
   where ta.school_id = p_school and ta.teacher_user_id = auth.uid()
     and ms_private.active_member(p_school, auth.uid(), 'teacher')
     and ms_private.active_member(p_school, ps.parent_user_id, 'parent')
   group by ps.student_id, st.first_name, st.last_name, ps.parent_user_id, p.full_name
$$;

create or replace function myschool.list_message_reports(p_school uuid, p_status text)
returns table (report_id uuid, status text, reason text, created_at timestamptz, thread_id uuid, message_id uuid,
               message_body text, sender_id uuid, sender_name text, reporter_name text, student_name text,
               parent_name text, teacher_name text, resolution_note text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not ms_private.is_school_admin(p_school) then raise exception 'not allowed' using errcode = '42501'; end if;
  return query
  select r.id, r.status, r.reason, r.created_at, r.thread_id, r.message_id, m.body, m.sender_id,
         coalesce(nullif(trim(sp.full_name), ''), 'Unnamed'), coalesce(nullif(trim(rp.full_name), ''), 'Unnamed'),
         trim(st.first_name || ' ' || st.last_name),
         coalesce(nullif(trim(pp.full_name), ''), 'Parent'), coalesce(nullif(trim(tp.full_name), ''), 'Teacher'),
         r.resolution_note
    from myschool.message_reports r
    join myschool.messages m on m.id = r.message_id
    join myschool.message_threads t on t.id = r.thread_id
    join myschool.students st on st.id = t.student_id
    left join myschool.profiles sp on sp.id = m.sender_id
    left join myschool.profiles rp on rp.id = r.reported_by
    left join myschool.profiles pp on pp.id = t.parent_user_id
    left join myschool.profiles tp on tp.id = t.teacher_user_id
   where r.school_id = p_school and (p_status is null or r.status = p_status)
   order by r.created_at desc;
end $$;

-- ---------------------------------------------------------------- privileges
revoke all on function
  ms_private.active_member(uuid, uuid, myschool.school_role), ms_private.parent_of_student(uuid, uuid, uuid),
  ms_private.teacher_teaches_student(uuid, uuid, uuid), ms_private.can_converse(uuid, uuid, uuid, uuid),
  ms_private.is_thread_participant(uuid), ms_private.thread_is_reported(uuid),
  ms_private.notify_new_message(uuid, uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function ms_private.is_thread_participant(uuid), ms_private.thread_is_reported(uuid) to authenticated;
revoke all on function
  myschool.start_message_thread(uuid, uuid, text, text), myschool.send_message(uuid, text),
  myschool.mark_thread_read(uuid), myschool.report_message(uuid, text),
  myschool.resolve_message_report(uuid, text, boolean), myschool.set_messaging_block(uuid, uuid, boolean, text),
  myschool.my_message_threads(uuid), myschool.my_message_contacts(uuid), myschool.list_message_reports(uuid, text)
  from public, anon, authenticated;
grant execute on function
  myschool.start_message_thread(uuid, uuid, text, text), myschool.send_message(uuid, text),
  myschool.mark_thread_read(uuid), myschool.report_message(uuid, text),
  myschool.resolve_message_report(uuid, text, boolean), myschool.set_messaging_block(uuid, uuid, boolean, text),
  myschool.my_message_threads(uuid), myschool.my_message_contacts(uuid), myschool.list_message_reports(uuid, text)
  to authenticated;
grant select on myschool.message_threads, myschool.messages, myschool.message_reports, myschool.message_blocks to authenticated;

notify pgrst, 'reload schema';
