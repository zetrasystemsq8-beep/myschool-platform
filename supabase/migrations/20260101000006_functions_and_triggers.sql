-- 06: authorization helpers (used by RLS), triggers, workflow RPCs, public search.
-- All helpers are SECURITY DEFINER with an empty search_path so RLS policies stay cheap and
-- cannot recurse. They NEVER take the user id as input: they always use auth.uid().

-- ---------------------------------------------------------------- identity helpers
create or replace function app.is_platform_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select p.is_platform_admin from public.profiles p where p.id = auth.uid()), false)
$$;

create or replace function app.has_role(p_school uuid, p_roles public.school_role[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.school_members m
    join public.schools s on s.id = m.school_id
    where m.school_id = p_school and m.user_id = auth.uid()
      and m.status = 'active' and s.is_active and m.role = any (p_roles))
$$;

create or replace function app.is_member(p_school uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.has_role(p_school, array['student','parent','teacher','school_admin']::public.school_role[])
$$;
create or replace function app.is_staff(p_school uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.has_role(p_school, array['teacher','school_admin']::public.school_role[])
$$;
create or replace function app.is_school_admin(p_school uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.has_role(p_school, array['school_admin']::public.school_role[])
$$;

create or replace function app.is_own_student(p_student uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.students st
    join public.school_members m on m.school_id = st.school_id and m.user_id = st.user_id
    join public.schools s on s.id = st.school_id
    where st.id = p_student and st.user_id = auth.uid() and m.status = 'active' and s.is_active)
$$;

create or replace function app.is_parent_of(p_student uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.parent_students ps
    join public.school_members m on m.school_id = ps.school_id and m.user_id = ps.parent_user_id
    join public.schools s on s.id = ps.school_id
    where ps.student_id = p_student and ps.parent_user_id = auth.uid()
      and m.status = 'active' and s.is_active)
$$;

create or replace function app.is_self_or_parent_of(p_student uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.is_own_student(p_student) or app.is_parent_of(p_student)
$$;

-- teacher teaches this class in this session
create or replace function app.teacher_assigned_class(p_school uuid, p_class uuid, p_session uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.has_role(p_school, array['teacher']::public.school_role[])
    and exists (select 1 from public.teaching_assignments ta
                where ta.school_id = p_school and ta.teacher_user_id = auth.uid()
                  and ta.class_id = p_class and ta.session_id = p_session)
$$;

-- teacher teaches (some subject to) a class this student is enrolled in
create or replace function app.teaches_student(p_student uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.enrollments e
    join public.teaching_assignments ta
      on ta.class_id = e.class_id and ta.session_id = e.session_id and ta.school_id = e.school_id
    where e.student_id = p_student and ta.teacher_user_id = auth.uid()
      and app.has_role(e.school_id, array['teacher']::public.school_role[]))
$$;

-- admin of the school OR the teacher assigned to this exact (term, class, subject)
create or replace function app.can_work_sheet_keys(p_school uuid, p_term uuid, p_class uuid, p_subject uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select app.is_school_admin(p_school)
    or (app.has_role(p_school, array['teacher']::public.school_role[])
        and exists (select 1 from public.terms t
                    join public.teaching_assignments ta on ta.session_id = t.session_id and ta.school_id = t.school_id
                    where t.id = p_term and t.school_id = p_school
                      and ta.teacher_user_id = auth.uid() and ta.class_id = p_class and ta.subject_id = p_subject))
$$;

create or replace function app.can_work_sheet(p_sheet uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select app.can_work_sheet_keys(s.school_id, s.term_id, s.class_id, s.subject_id)
                   from public.result_sheets s where s.id = p_sheet), false)
$$;

create or replace function app.sheet_is_published(p_sheet uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.result_sheets s where s.id = p_sheet and s.status = 'published')
$$;

-- who may insert/update/delete items: teacher/admin while draft; admin only while submitted
create or replace function app.can_edit_items(p_sheet uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select (s.status = 'draft' and app.can_work_sheet_keys(s.school_id, s.term_id, s.class_id, s.subject_id))
        or (s.status = 'submitted' and app.is_school_admin(s.school_id))
    from public.result_sheets s where s.id = p_sheet), false)
$$;

create or replace function app.announcement_visible(p_school uuid, p_audience public.announcement_audience) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.school_members m join public.schools s on s.id = m.school_id
    where m.school_id = p_school and m.user_id = auth.uid() and m.status = 'active' and s.is_active
      and (p_audience = 'all'
        or (p_audience = 'students' and m.role = 'student')
        or (p_audience = 'parents'  and m.role = 'parent')
        or (p_audience = 'staff'    and m.role in ('teacher', 'school_admin'))))
$$;

-- a school admin may see profiles of people in schools they administer
create or replace function app.admin_of_profile(p_profile uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.school_members target
    where target.user_id = p_profile and app.is_school_admin(target.school_id))
$$;

-- ---------------------------------------------------------------- audit
create or replace function app.write_audit(p_school uuid, p_action text, p_entity_type text,
                                           p_entity_id uuid, p_metadata jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare v_role text;
begin
  select m.role::text into v_role from public.school_members m
   where m.school_id = p_school and m.user_id = auth.uid();
  if v_role is null and app.is_platform_admin() then v_role := 'platform_admin'; end if;
  insert into public.audit_logs (school_id, actor_id, actor_role, action, entity_type, entity_id, metadata)
  values (p_school, auth.uid(), v_role, p_action, p_entity_type, p_entity_id, coalesce(p_metadata, '{}'::jsonb));
end $$;

create or replace function app.audit_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_row jsonb; v_old jsonb; v_changed jsonb; v_school uuid; v_id uuid; v_action text;
begin
  v_action := tg_argv[0] || '.' || case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' else 'deleted' end;
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_school := nullif(v_row ->> 'school_id', '')::uuid;
  v_id := coalesce(nullif(v_row ->> 'id', ''), nullif(v_row ->> 'school_id', ''))::uuid;
  if tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    select jsonb_object_agg(n.key, jsonb_build_object('old', v_old -> n.key, 'new', n.value)) into v_changed
      from jsonb_each(v_row) n
     where n.key <> 'updated_at' and (v_old -> n.key) is distinct from n.value;
    if v_changed is not null then
      perform app.write_audit(v_school, v_action, tg_argv[0], v_id, jsonb_build_object('changed', v_changed));
    end if;
    return new;
  elsif tg_op = 'INSERT' then
    perform app.write_audit(v_school, v_action, tg_argv[0], v_id, jsonb_build_object('after', v_row));
    return new;
  else
    perform app.write_audit(v_school, v_action, tg_argv[0], v_id, jsonb_build_object('before', v_row));
    return old;
  end if;
end $$;

create or replace function app.audit_logs_immutable() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' and coalesce(current_setting('app.allow_audit_purge', true), '') = 'on' then
    return old;
  end if;
  raise exception 'audit_logs is append-only' using errcode = '42501';
end $$;
create trigger audit_logs_no_change before update or delete on public.audit_logs
  for each row execute function app.audit_logs_immutable();

-- audit triggers on the tables whose changes matter
create trigger audit_result_items after insert or update or delete on public.result_items
  for each row execute function app.audit_row('result_item');
create trigger audit_announcements after insert or update or delete on public.announcements
  for each row execute function app.audit_row('announcement');
create trigger audit_members after insert or update or delete on public.school_members
  for each row execute function app.audit_row('school_member');
create trigger audit_students after insert or update or delete on public.students
  for each row execute function app.audit_row('student');
create trigger audit_assignments after insert or update or delete on public.teaching_assignments
  for each row execute function app.audit_row('teaching_assignment');
create trigger audit_settings after insert or update on public.school_settings
  for each row execute function app.audit_row('school_settings');
create trigger audit_grading after insert or update or delete on public.grading_scales
  for each row execute function app.audit_row('grading_scale');

-- ---------------------------------------------------------------- generic triggers
create or replace function app.forbid_school_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.school_id is distinct from old.school_id then
    raise exception 'school_id is immutable' using errcode = '23514';
  end if;
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['schools','school_settings','profiles','students','student_private',
                           'result_sheets','result_items','announcements'] loop
    execute format('create trigger touch_updated_at before update on public.%I
                    for each row execute function app.touch_updated_at()', t);
  end loop;
  -- a row may never move to another school
  foreach t in array array['students','classes','subjects','academic_sessions','terms','enrollments',
                           'teaching_assignments','result_sheets','result_items','announcements',
                           'school_members','parent_students','student_private'] loop
    execute format('create trigger forbid_school_change before update on public.%I
                    for each row execute function app.forbid_school_change()', t);
  end loop;
end $$;


-- profile auto-creation (accounts are provisioned server-side; role data is NEVER taken from metadata)
create or replace function app.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, nullif(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function app.handle_new_user();

-- the linked user must hold the right role in THIS school
create or replace function app.assert_member_role() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_user uuid := nullif(to_jsonb(new) ->> tg_argv[0], '')::uuid;
begin
  if v_user is null then return new; end if;
  if not exists (select 1 from public.school_members m
                 where m.school_id = new.school_id and m.user_id = v_user
                   and m.role = tg_argv[1]::public.school_role) then
    raise exception 'user is not a % of this school', tg_argv[1] using errcode = '23514';
  end if;
  return new;
end $$;
create trigger students_user_role before insert or update on public.students
  for each row execute function app.assert_member_role('user_id', 'student');
create trigger parent_students_role before insert or update on public.parent_students
  for each row execute function app.assert_member_role('parent_user_id', 'parent');
create trigger assignments_role before insert or update on public.teaching_assignments
  for each row execute function app.assert_member_role('teacher_user_id', 'teacher');

-- announcements: stamp author and publication time server-side
create or replace function app.announcement_before_write() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'INSERT' then new.author_id := coalesce(auth.uid(), new.author_id); end if;
  if new.status = 'published' and new.published_at is null then new.published_at := now(); end if;
  return new;
end $$;
create trigger announcements_before_write before insert or update on public.announcements
  for each row execute function app.announcement_before_write();

-- result items: validate against school settings, compute total + grade, check enrollment
create or replace function app.result_item_before_write() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_set public.school_settings; v_sheet public.result_sheets; v_session uuid;
begin
  if tg_op = 'UPDATE' and (new.sheet_id <> old.sheet_id or new.student_id <> old.student_id) then
    raise exception 'sheet_id and student_id cannot be changed' using errcode = '23514';
  end if;

  select * into v_set from public.school_settings where school_id = new.school_id;
  if new.ca_score is not null and new.ca_score > v_set.ca_max then
    raise exception 'ca_score % exceeds maximum %', new.ca_score, v_set.ca_max using errcode = '23514';
  end if;
  if new.exam_score is not null and new.exam_score > v_set.exam_max then
    raise exception 'exam_score % exceeds maximum %', new.exam_score, v_set.exam_max using errcode = '23514';
  end if;

  if tg_op = 'INSERT' then
    select * into v_sheet from public.result_sheets where id = new.sheet_id;
    select session_id into v_session from public.terms where id = v_sheet.term_id;
    if not exists (select 1 from public.enrollments e
                   where e.student_id = new.student_id and e.class_id = v_sheet.class_id
                     and e.session_id = v_session and e.status <> 'withdrawn') then
      raise exception 'student is not enrolled in this class for this session' using errcode = '23514';
    end if;
  end if;

  if new.ca_score is null and new.exam_score is null then
    new.total := null; new.grade := null;
  else
    new.total := coalesce(new.ca_score, 0) + coalesce(new.exam_score, 0);
    select g.grade into new.grade from public.grading_scales g
     where g.school_id = new.school_id and g.min_score <= new.total
     order by g.min_score desc limit 1;
  end if;
  new.entered_by := coalesce(auth.uid(), new.entered_by);
  return new;
end $$;
create trigger result_items_before_write before insert or update on public.result_items
  for each row execute function app.result_item_before_write();

-- sheet status may only change inside the workflow functions below
create or replace function app.guard_sheet_status() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status is distinct from old.status
     and coalesce(current_setting('app.sheet_transition', true), '') <> 'on' then
    raise exception 'status can only change through the workflow functions' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger result_sheets_guard_status before update on public.result_sheets
  for each row execute function app.guard_sheet_status();

-- ---------------------------------------------------------------- result workflow
create or replace function app.transition_sheet(p_sheet uuid, p_from public.result_status[],
    p_to public.result_status, p_action text, p_note text default null) returns public.result_sheets
language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_sheet public.result_sheets; v_set public.school_settings; v_missing int;
begin
  if v_uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into v_sheet from public.result_sheets where id = p_sheet for update;
  if not found then raise exception 'result sheet not found' using errcode = 'P0002'; end if;

  if p_action = 'submitted' then
    if not app.can_work_sheet_keys(v_sheet.school_id, v_sheet.term_id, v_sheet.class_id, v_sheet.subject_id) then
      raise exception 'not allowed' using errcode = '42501';
    end if;
  elsif not app.is_school_admin(v_sheet.school_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  if not (v_sheet.status = any (p_from)) then
    raise exception 'sheet is % and cannot be %', v_sheet.status, p_action using errcode = '55000';
  end if;
  if p_action in ('returned', 'unpublished') and nullif(trim(p_note), '') is null then
    raise exception 'a reason is required' using errcode = '22023';
  end if;

  if p_action = 'submitted' then
    select count(*) into v_missing
      from public.enrollments e
      join public.terms t on t.id = v_sheet.term_id
     where e.class_id = v_sheet.class_id and e.session_id = t.session_id and e.status <> 'withdrawn'
       and not exists (select 1 from public.result_items i
                       where i.sheet_id = v_sheet.id and i.student_id = e.student_id and i.total is not null);
    if v_missing > 0 then
      raise exception '% enrolled student(s) have no score yet', v_missing using errcode = '23514';
    end if;
  elsif p_action = 'approved' then
    select * into v_set from public.school_settings where school_id = v_sheet.school_id;
    if v_set.require_separate_approver and v_sheet.submitted_by = v_uid then
      raise exception 'approver must differ from submitter' using errcode = '42501';
    end if;
  end if;

  perform set_config('app.sheet_transition', 'on', true);
  update public.result_sheets set
    status       = p_to,
    submitted_by = case p_action when 'submitted' then v_uid when 'returned' then null else submitted_by end,
    submitted_at = case p_action when 'submitted' then now() when 'returned' then null else submitted_at end,
    approved_by  = case p_action when 'approved' then v_uid when 'returned' then null else approved_by end,
    approved_at  = case p_action when 'approved' then now() when 'returned' then null else approved_at end,
    published_by = case p_action when 'published' then v_uid when 'unpublished' then null else published_by end,
    published_at = case p_action when 'published' then now() when 'unpublished' then null else published_at end,
    return_note  = case when p_action in ('returned', 'unpublished') then p_note
                        when p_action = 'submitted' then null else return_note end
   where id = p_sheet returning * into v_sheet;
  perform set_config('app.sheet_transition', 'off', true);

  perform app.write_audit(v_sheet.school_id, 'result_sheet.' || p_action, 'result_sheet', v_sheet.id,
    jsonb_build_object('from', p_from, 'to', p_to, 'note', p_note, 'term_id', v_sheet.term_id,
                       'class_id', v_sheet.class_id, 'subject_id', v_sheet.subject_id));
  return v_sheet;
end $$;

create or replace function public.submit_result_sheet(p_sheet_id uuid) returns public.result_sheets
language sql security definer set search_path = '' as $$
  select * from app.transition_sheet(p_sheet_id, array['draft']::public.result_status[], 'submitted', 'submitted')
$$;
create or replace function public.return_result_sheet(p_sheet_id uuid, p_note text) returns public.result_sheets
language sql security definer set search_path = '' as $$
  select * from app.transition_sheet(p_sheet_id, array['submitted','approved']::public.result_status[], 'draft', 'returned', p_note)
$$;
create or replace function public.approve_result_sheet(p_sheet_id uuid) returns public.result_sheets
language sql security definer set search_path = '' as $$
  select * from app.transition_sheet(p_sheet_id, array['submitted']::public.result_status[], 'approved', 'approved')
$$;
create or replace function public.publish_result_sheet(p_sheet_id uuid) returns public.result_sheets
language sql security definer set search_path = '' as $$
  select * from app.transition_sheet(p_sheet_id, array['approved']::public.result_status[], 'published', 'published')
$$;
create or replace function public.unpublish_result_sheet(p_sheet_id uuid, p_reason text) returns public.result_sheets
language sql security definer set search_path = '' as $$
  select * from app.transition_sheet(p_sheet_id, array['published']::public.result_status[], 'approved', 'unpublished', p_reason)
$$;

-- ---------------------------------------------------------------- platform admin RPCs
create or replace function public.create_school(p_school_code text, p_name text, p_motto text default null,
    p_city text default null, p_state text default null) returns public.schools
language plpgsql security definer set search_path = '' as $$
declare v_school public.schools;
begin
  if not app.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  insert into public.schools (school_code, name, motto, city, state)
  values (upper(trim(p_school_code)), trim(p_name), p_motto, p_city, p_state) returning * into v_school;
  insert into public.school_settings (school_id) values (v_school.id);
  insert into public.grading_scales (school_id, grade, min_score, remark) values
    (v_school.id, 'A', 70, 'Excellent'), (v_school.id, 'B', 60, 'Very Good'),
    (v_school.id, 'C', 50, 'Good'),      (v_school.id, 'D', 45, 'Fair'),
    (v_school.id, 'E', 40, 'Pass'),      (v_school.id, 'F', 0,  'Fail');
  perform app.write_audit(v_school.id, 'school.created', 'school', v_school.id,
                          jsonb_build_object('school_code', v_school.school_code));
  return v_school;
end $$;

create or replace function public.set_school_status(p_school_id uuid, p_active boolean, p_listed boolean) returns public.schools
language plpgsql security definer set search_path = '' as $$
declare v_school public.schools;
begin
  if not app.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  update public.schools set is_active = p_active, is_listed = p_listed where id = p_school_id returning * into v_school;
  if not found then raise exception 'school not found' using errcode = 'P0002'; end if;
  perform app.write_audit(p_school_id, 'school.status_changed', 'school', p_school_id,
                          jsonb_build_object('is_active', p_active, 'is_listed', p_listed));
  return v_school;
end $$;

-- ---------------------------------------------------------------- public discovery (anon-safe)
-- Returns ONLY intentionally public columns, only for active + listed schools.
create or replace function public.search_schools(q text, max_results integer default 20)
returns table (id uuid, school_code text, name text, motto text, logo_path text, city text, state text)
language sql stable security definer set search_path = '' as $$
  with p as (select trim(coalesce(q, '')) as raw,
                    regexp_replace(trim(coalesce(q, '')), '([\\%_])', '\\\1', 'g') as pat)
  select s.id, s.school_code, s.name, s.motto, s.logo_path, s.city, s.state
    from public.schools s, p
   where s.is_active and s.is_listed and char_length(p.raw) between 2 and 100
     and (s.school_code like upper(p.pat) || '%' or s.name ilike '%' || p.pat || '%')
   order by (s.school_code = upper(p.raw)) desc, s.name
   limit least(greatest(coalesce(max_results, 20), 1), 20)
$$;

create or replace function public.get_public_school(p_school_code text)
returns table (id uuid, school_code text, name text, motto text, description text, logo_path text,
               website text, city text, state text, country text)
language sql stable security definer set search_path = '' as $$
  select s.id, s.school_code, s.name, s.motto, s.description, s.logo_path, s.website, s.city, s.state, s.country
    from public.schools s
   where s.school_code = upper(trim(p_school_code)) and s.is_active and s.is_listed
$$;

-- ---------------------------------------------------------------- student/parent read model
-- security_invoker: RLS of the caller applies, so a student sees only their own published rows,
-- a parent only their children's, staff only what their policies allow.
create view public.published_results with (security_invoker = true) as
select i.id as item_id, i.school_id, i.student_id,
       sess.id as session_id, sess.name as session_name,
       t.id as term_id, t.term_number, t.name as term_name,
       c.name as class_name, sub.id as subject_id, sub.name as subject_name, sub.code as subject_code,
       i.ca_score, i.exam_score, i.total, i.grade, i.remark, sh.published_at
  from public.result_items i
  join public.result_sheets sh on sh.id = i.sheet_id and sh.status = 'published'
  join public.terms t on t.id = sh.term_id
  join public.academic_sessions sess on sess.id = t.session_id
  join public.classes c on c.id = sh.class_id
  join public.subjects sub on sub.id = sh.subject_id;

-- ---------------------------------------------------------------- function privileges
revoke all on all functions in schema app from public, anon, authenticated;
grant execute on function
  app.is_platform_admin(), app.has_role(uuid, public.school_role[]), app.is_member(uuid), app.is_staff(uuid),
  app.is_school_admin(uuid), app.is_own_student(uuid), app.is_parent_of(uuid), app.is_self_or_parent_of(uuid),
  app.teacher_assigned_class(uuid, uuid, uuid), app.teaches_student(uuid),
  app.can_work_sheet_keys(uuid, uuid, uuid, uuid), app.can_work_sheet(uuid), app.sheet_is_published(uuid),
  app.can_edit_items(uuid), app.announcement_visible(uuid, public.announcement_audience),
  app.admin_of_profile(uuid)
  to authenticated;
-- write_audit / transition_sheet / triggers are intentionally NOT executable by clients.

revoke all on function public.submit_result_sheet(uuid), public.return_result_sheet(uuid, text),
  public.approve_result_sheet(uuid), public.publish_result_sheet(uuid), public.unpublish_result_sheet(uuid, text),
  public.create_school(text, text, text, text, text), public.set_school_status(uuid, boolean, boolean),
  public.search_schools(text, integer), public.get_public_school(text) from public, anon, authenticated;
grant execute on function
  public.submit_result_sheet(uuid), public.return_result_sheet(uuid, text), public.approve_result_sheet(uuid),
  public.publish_result_sheet(uuid), public.unpublish_result_sheet(uuid, text),
  public.create_school(text, text, text, text, text), public.set_school_status(uuid, boolean, boolean)
  to authenticated;
grant execute on function public.search_schools(text, integer), public.get_public_school(text) to anon, authenticated;
