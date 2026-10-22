-- 17: moving students up a school year, and changing a student's status (graduated, withdrawn, transferred ...).
-- Both are admin-only, audited functions so that enrollments, class registers and sign-in always stay consistent.

-- Student status. Sign-in follows it: withdrawn / transferred / suspended students cannot sign in; graduated ones still can
-- (to look at their results). Leaving the school also takes the student off the current year's class lists.
create or replace function myschool.set_student_status(p_student uuid, p_status myschool.student_status, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare st myschool.students;
begin
  select * into st from myschool.students where id = p_student;
  if st.id is null or not ms_private.is_school_admin(st.school_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if st.status = p_status then return; end if;

  update myschool.students set status = p_status where id = p_student;

  if st.user_id is not null then
    update myschool.school_members
       set status = (case when p_status::text in ('withdrawn', 'transferred', 'suspended') then 'suspended' else 'active' end)::myschool.member_status
     where school_id = st.school_id and user_id = st.user_id;
  end if;

  if p_status::text in ('withdrawn', 'transferred') then
    update myschool.enrollments e set status = 'withdrawn'
      from myschool.academic_sessions s
     where e.student_id = p_student and e.session_id = s.id and s.is_current and e.status = 'active';
  elsif p_status::text = 'active' and st.status::text in ('withdrawn', 'transferred') then
    update myschool.enrollments e set status = 'active'
      from myschool.academic_sessions s
     where e.student_id = p_student and e.session_id = s.id and s.is_current and e.status = 'withdrawn';
  end if;

  perform ms_private.write_audit(st.school_id, 'student.status_changed', 'student', p_student,
    jsonb_build_object('from', st.status, 'to', p_status, 'reason', nullif(trim(coalesce(p_reason, '')), '')));
end $$;

-- Moves the active students of ONE class from one school year into the next.
--   p_to_class null  -> the class graduates (students become "graduated")
--   p_repeat         -> students who repeat: they stay in the same class in the new year
-- Students already enrolled in the new year are skipped, so it is safe to run again.
create or replace function myschool.promote_class(
  p_from_session uuid, p_to_session uuid, p_from_class uuid, p_to_class uuid, p_repeat uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_school uuid; v_promoted integer := 0; v_repeated integer := 0; v_graduated integer := 0; v_skipped integer := 0;
  r record;
begin
  select school_id into v_school from myschool.classes where id = p_from_class;
  if v_school is null or not ms_private.is_school_admin(v_school) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_from_session = p_to_session then
    raise exception 'Choose two different school years.' using errcode = '22023';
  end if;
  if not exists (select 1 from myschool.academic_sessions where id = p_from_session and school_id = v_school)
     or not exists (select 1 from myschool.academic_sessions where id = p_to_session and school_id = v_school) then
    raise exception 'Choose school years of this school.' using errcode = '22023';
  end if;
  if p_to_class is not null and not exists (select 1 from myschool.classes where id = p_to_class and school_id = v_school) then
    raise exception 'Choose a class of this school.' using errcode = '22023';
  end if;

  for r in
    select en.id as enrollment_id, en.student_id
      from myschool.enrollments en
      join myschool.students st on st.id = en.student_id
     where en.school_id = v_school and en.session_id = p_from_session and en.class_id = p_from_class
       and en.status = 'active' and st.status = 'active'
  loop
    if exists (select 1 from myschool.enrollments x where x.student_id = r.student_id and x.session_id = p_to_session) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    if r.student_id = any (coalesce(p_repeat, '{}'::uuid[])) then
      insert into myschool.enrollments (school_id, student_id, class_id, session_id)
      values (v_school, r.student_id, p_from_class, p_to_session);
      update myschool.enrollments set status = 'repeated' where id = r.enrollment_id;
      v_repeated := v_repeated + 1;
    elsif p_to_class is null then
      update myschool.students set status = 'graduated' where id = r.student_id;
      update myschool.enrollments set status = 'promoted' where id = r.enrollment_id;
      v_graduated := v_graduated + 1;
    else
      insert into myschool.enrollments (school_id, student_id, class_id, session_id)
      values (v_school, r.student_id, p_to_class, p_to_session);
      update myschool.enrollments set status = 'promoted' where id = r.enrollment_id;
      v_promoted := v_promoted + 1;
    end if;
  end loop;

  perform ms_private.write_audit(v_school, 'promotion.run', 'class', p_from_class,
    jsonb_build_object('from_session', p_from_session, 'to_session', p_to_session, 'to_class', p_to_class,
                       'promoted', v_promoted, 'repeated', v_repeated, 'graduated', v_graduated, 'skipped', v_skipped));
  return jsonb_build_object('promoted', v_promoted, 'repeated', v_repeated, 'graduated', v_graduated, 'skipped', v_skipped);
end $$;

-- Keeps the same teachers on the same classes and subjects in the new year (active teachers only). Safe to run again.
create or replace function myschool.copy_teaching_assignments(p_from_session uuid, p_to_session uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_school uuid; v_n integer;
begin
  select school_id into v_school from myschool.academic_sessions where id = p_from_session;
  if v_school is null or not ms_private.is_school_admin(v_school) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if not exists (select 1 from myschool.academic_sessions where id = p_to_session and school_id = v_school) then
    raise exception 'Choose school years of this school.' using errcode = '22023';
  end if;
  insert into myschool.teaching_assignments (school_id, teacher_user_id, class_id, subject_id, session_id)
  select ta.school_id, ta.teacher_user_id, ta.class_id, ta.subject_id, p_to_session
    from myschool.teaching_assignments ta
    join myschool.school_members m on m.school_id = ta.school_id and m.user_id = ta.teacher_user_id and m.status = 'active'
   where ta.school_id = v_school and ta.session_id = p_from_session
  on conflict (teacher_user_id, class_id, subject_id, session_id) do nothing;
  get diagnostics v_n = row_count;
  perform ms_private.write_audit(v_school, 'promotion.assignments_copied', 'academic_session', p_to_session,
                                 jsonb_build_object('from_session', p_from_session, 'copied', v_n));
  return v_n;
end $$;

revoke all on function
  myschool.set_student_status(uuid, myschool.student_status, text),
  myschool.promote_class(uuid, uuid, uuid, uuid, uuid[]),
  myschool.copy_teaching_assignments(uuid, uuid)
  from public, anon, authenticated;
grant execute on function
  myschool.set_student_status(uuid, myschool.student_status, text),
  myschool.promote_class(uuid, uuid, uuid, uuid, uuid[]),
  myschool.copy_teaching_assignments(uuid, uuid)
  to authenticated;

notify pgrst, 'reload schema';
