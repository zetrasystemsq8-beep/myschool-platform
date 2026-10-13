-- 11: student attendance. Marking goes through ONE audited RPC; clients never write the table directly.
create type myschool.attendance_status as enum ('present', 'absent', 'late');

-- Today's date in the school's own time zone (school_settings.timezone, default Africa/Lagos).
create or replace function ms_private.school_today(p_school uuid) returns date
language sql stable security definer set search_path = '' as $$
  select (now() at time zone coalesce(
            (select s.timezone from myschool.school_settings s where s.school_id = p_school),
            'Africa/Lagos'))::date
$$;

create table myschool.attendance_records (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null,
  class_id        uuid not null,
  student_id      uuid not null,
  attendance_date date not null,
  status          myschool.attendance_status not null,
  note            text check (note is null or char_length(note) <= 200),
  marked_by       uuid default auth.uid() references myschool.profiles (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- the duplicate rule: one record per student, class and day
  unique (student_id, class_id, attendance_date),
  foreign key (class_id, school_id) references myschool.classes (id, school_id) on delete restrict,
  foreign key (student_id, school_id) references myschool.students (id, school_id) on delete restrict
);
create index attendance_class_date_idx on myschool.attendance_records (class_id, attendance_date);
create index attendance_student_date_idx on myschool.attendance_records (student_id, attendance_date);

create trigger touch_updated_at before update on myschool.attendance_records
  for each row execute function ms_private.touch_updated_at();
create trigger forbid_school_change before update on myschool.attendance_records
  for each row execute function ms_private.forbid_school_change();

-- Rules that belong to the data itself: no future dates, student really in that class that day.
create or replace function ms_private.attendance_before_write() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.attendance_date > ms_private.school_today(new.school_id) then
    raise exception 'Attendance cannot be marked for a future date.' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' and (new.student_id <> old.student_id or new.class_id <> old.class_id
                           or new.attendance_date <> old.attendance_date) then
    raise exception 'Student, class and date cannot be changed.' using errcode = '23514';
  end if;
  if not exists (
       select 1 from myschool.enrollments e
       join myschool.academic_sessions s on s.id = e.session_id
       where e.student_id = new.student_id and e.class_id = new.class_id and e.school_id = new.school_id
         and e.status <> 'withdrawn'
         and new.attendance_date between s.start_date and s.end_date) then
    raise exception 'This student is not enrolled in this class on that date.' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger attendance_before_write before insert or update on myschool.attendance_records
  for each row execute function ms_private.attendance_before_write();

-- Teachers see classes they teach (any subject); admins see everything in the school.
create or replace function ms_private.teacher_has_class(p_school uuid, p_class uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select ms_private.has_role(p_school, array['teacher']::myschool.school_role[])
     and exists (select 1 from myschool.teaching_assignments ta
                 where ta.school_id = p_school and ta.class_id = p_class and ta.teacher_user_id = auth.uid())
$$;

-- Admin: any date up to today. Teacher: only their classes, today back to 7 days ago, inside a school year they teach.
create or replace function ms_private.can_mark_attendance(p_school uuid, p_class uuid, p_date date) returns boolean
language sql stable security definer set search_path = '' as $$
  select ms_private.is_school_admin(p_school)
      or (ms_private.has_role(p_school, array['teacher']::myschool.school_role[])
          and p_date <= ms_private.school_today(p_school)
          and p_date >= ms_private.school_today(p_school) - 7
          and exists (select 1 from myschool.teaching_assignments ta
                      join myschool.academic_sessions s on s.id = ta.session_id
                      where ta.school_id = p_school and ta.class_id = p_class
                        and ta.teacher_user_id = auth.uid()
                        and p_date between s.start_date and s.end_date))
$$;

alter table myschool.attendance_records enable row level security;
create policy attendance_select on myschool.attendance_records for select to authenticated
  using (ms_private.is_school_admin(school_id)
         or ms_private.is_self_or_parent_of(student_id)
         or ms_private.teacher_has_class(school_id, class_id));
-- No INSERT/UPDATE/DELETE policies: all writes go through mark_attendance().

-- p_entries: [{"student_id": "...", "status": "present|absent|late", "note": "optional"}], max 200.
create or replace function myschool.mark_attendance(p_class_id uuid, p_date date, p_entries jsonb)
returns integer
language plpgsql security definer set search_path = '' as $$
declare v_school uuid; v_e jsonb; v_n integer := 0;
begin
  if auth.uid() is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select school_id into v_school from myschool.classes where id = p_class_id;
  if v_school is null then raise exception 'class not found' using errcode = 'P0002'; end if;
  if not ms_private.can_mark_attendance(v_school, p_class_id, p_date) then
    raise exception 'You cannot mark attendance for this class on this date.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_entries) <> 'array' or jsonb_array_length(p_entries) = 0 or jsonb_array_length(p_entries) > 200 then
    raise exception 'Send between 1 and 200 entries.' using errcode = '22023';
  end if;
  for v_e in select * from jsonb_array_elements(p_entries) loop
    insert into myschool.attendance_records (school_id, class_id, student_id, attendance_date, status, note, marked_by)
    values (v_school, p_class_id, (v_e ->> 'student_id')::uuid, p_date,
            (v_e ->> 'status')::myschool.attendance_status, nullif(left(coalesce(v_e ->> 'note', ''), 200), ''), auth.uid())
    on conflict (student_id, class_id, attendance_date)
    do update set status = excluded.status, note = excluded.note, marked_by = auth.uid();
    v_n := v_n + 1;
  end loop;
  perform ms_private.write_audit(v_school, 'attendance.marked', 'class', p_class_id,
                                 jsonb_build_object('date', p_date, 'entries', v_n));
  return v_n;
end $$;

-- Staff summaries (students/parents never get these, they read their own records instead).
create view myschool.attendance_daily_summary with (security_invoker = true) as
select a.school_id, a.class_id, c.name as class_name, a.attendance_date,
       count(*) filter (where a.status = 'present')::int as present,
       count(*) filter (where a.status = 'late')::int as late,
       count(*) filter (where a.status = 'absent')::int as absent
  from myschool.attendance_records a
  join myschool.classes c on c.id = a.class_id
 where ms_private.is_staff(a.school_id)
 group by a.school_id, a.class_id, c.name, a.attendance_date;

revoke all on function ms_private.school_today(uuid), ms_private.attendance_before_write(),
  ms_private.teacher_has_class(uuid, uuid), ms_private.can_mark_attendance(uuid, uuid, date)
  from public, anon, authenticated;
grant execute on function ms_private.teacher_has_class(uuid, uuid), ms_private.can_mark_attendance(uuid, uuid, date)
  to authenticated;
revoke all on function myschool.mark_attendance(uuid, date, jsonb) from public, anon, authenticated;
grant execute on function myschool.mark_attendance(uuid, date, jsonb) to authenticated;
grant select on myschool.attendance_records, myschool.attendance_daily_summary to authenticated;

notify pgrst, 'reload schema';
