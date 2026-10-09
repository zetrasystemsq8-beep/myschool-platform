-- 07: Row Level Security. Default = deny. Every policy below is the ONLY way a row becomes visible.
-- Tenant isolation: every policy is anchored on school_id through app.* helpers that check an
-- ACTIVE membership of auth.uid() in that exact school.

alter table myschool.schools              enable row level security;
alter table myschool.school_settings      enable row level security;
alter table myschool.grading_scales       enable row level security;
alter table myschool.profiles             enable row level security;
alter table myschool.school_members       enable row level security;
alter table myschool.academic_sessions    enable row level security;
alter table myschool.terms                enable row level security;
alter table myschool.classes              enable row level security;
alter table myschool.subjects             enable row level security;
alter table myschool.students             enable row level security;
alter table myschool.student_private      enable row level security;
alter table myschool.parent_students      enable row level security;
alter table myschool.teaching_assignments enable row level security;
alter table myschool.enrollments          enable row level security;
alter table myschool.result_sheets        enable row level security;
alter table myschool.result_items         enable row level security;
alter table myschool.script_scans         enable row level security;
alter table myschool.announcements        enable row level security;
alter table myschool.audit_logs           enable row level security;

-- ---------------------------------------------------------------- schools & settings
create policy schools_select on myschool.schools for select to authenticated
  using (ms_private.is_member(id) or ms_private.is_platform_admin());
create policy schools_update on myschool.schools for update to authenticated
  using (ms_private.is_school_admin(id)) with check (ms_private.is_school_admin(id));  -- columns limited by GRANT

create policy settings_select on myschool.school_settings for select to authenticated
  using (ms_private.is_member(school_id) or ms_private.is_platform_admin());
create policy settings_update on myschool.school_settings for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));

create policy grading_select on myschool.grading_scales for select to authenticated
  using (ms_private.is_member(school_id));
create policy grading_insert on myschool.grading_scales for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy grading_update on myschool.grading_scales for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));
create policy grading_delete on myschool.grading_scales for delete to authenticated
  using (ms_private.is_school_admin(school_id));

-- ---------------------------------------------------------------- identity & membership
create policy profiles_select on myschool.profiles for select to authenticated
  using (id = (select auth.uid()) or ms_private.admin_of_profile(id) or ms_private.is_platform_admin());
create policy profiles_update on myschool.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid())); -- is_platform_admin not grantable

create policy members_select on myschool.school_members for select to authenticated
  using (user_id = (select auth.uid()) or ms_private.is_school_admin(school_id) or ms_private.is_platform_admin());
create policy members_update on myschool.school_members for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));
-- INSERT/DELETE on school_members: server side only (Edge Function with service role).

-- ---------------------------------------------------------------- academic structure
do $$
declare t text;
begin
  foreach t in array array['academic_sessions', 'terms', 'classes', 'subjects'] loop
    execute format('create policy %1$s_select on myschool.%1$I for select to authenticated using (ms_private.is_member(school_id))', t);
    execute format('create policy %1$s_insert on myschool.%1$I for insert to authenticated with check (ms_private.is_school_admin(school_id))', t);
    execute format('create policy %1$s_update on myschool.%1$I for update to authenticated using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id))', t);
    execute format('create policy %1$s_delete on myschool.%1$I for delete to authenticated using (ms_private.is_school_admin(school_id))', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- people
create policy students_select on myschool.students for select to authenticated
  using (ms_private.is_school_admin(school_id) or ms_private.is_self_or_parent_of(id) or ms_private.teaches_student(id));
create policy students_insert on myschool.students for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy students_update on myschool.students for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));
create policy students_delete on myschool.students for delete to authenticated
  using (ms_private.is_school_admin(school_id));

-- teachers are deliberately NOT able to read this table
create policy student_private_select on myschool.student_private for select to authenticated
  using (ms_private.is_school_admin(school_id) or ms_private.is_self_or_parent_of(student_id));
create policy student_private_insert on myschool.student_private for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy student_private_update on myschool.student_private for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));
create policy student_private_delete on myschool.student_private for delete to authenticated
  using (ms_private.is_school_admin(school_id));

create policy parent_students_select on myschool.parent_students for select to authenticated
  using (parent_user_id = (select auth.uid()) or ms_private.is_school_admin(school_id));
create policy parent_students_insert on myschool.parent_students for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy parent_students_delete on myschool.parent_students for delete to authenticated
  using (ms_private.is_school_admin(school_id));

create policy assignments_select on myschool.teaching_assignments for select to authenticated
  using (ms_private.is_school_admin(school_id) or teacher_user_id = (select auth.uid()));
create policy assignments_insert on myschool.teaching_assignments for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy assignments_delete on myschool.teaching_assignments for delete to authenticated
  using (ms_private.is_school_admin(school_id));

create policy enrollments_select on myschool.enrollments for select to authenticated
  using (ms_private.is_school_admin(school_id) or ms_private.is_self_or_parent_of(student_id)
         or ms_private.teacher_assigned_class(school_id, class_id, session_id));
create policy enrollments_insert on myschool.enrollments for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy enrollments_update on myschool.enrollments for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));
create policy enrollments_delete on myschool.enrollments for delete to authenticated
  using (ms_private.is_school_admin(school_id));

-- ---------------------------------------------------------------- results
-- Sheets: admin + assigned teacher always; students/parents ONLY when published.
create policy sheets_select on myschool.result_sheets for select to authenticated
  using (ms_private.can_work_sheet_keys(school_id, term_id, class_id, subject_id)
         or (status = 'published' and ms_private.has_role(school_id, array['student','parent']::myschool.school_role[])));
create policy sheets_insert on myschool.result_sheets for insert to authenticated
  with check (status = 'draft' and created_by = (select auth.uid())
              and ms_private.can_work_sheet_keys(school_id, term_id, class_id, subject_id));
create policy sheets_delete on myschool.result_sheets for delete to authenticated
  using (status = 'draft' and ms_private.is_school_admin(school_id));
-- No UPDATE policy: status moves only through the workflow RPCs (security definer).

create policy items_select on myschool.result_items for select to authenticated
  using (ms_private.can_work_sheet(sheet_id)
         or (ms_private.sheet_is_published(sheet_id) and ms_private.is_self_or_parent_of(student_id)));
create policy items_insert on myschool.result_items for insert to authenticated
  with check (ms_private.can_edit_items(sheet_id));
create policy items_update on myschool.result_items for update to authenticated
  using (ms_private.can_edit_items(sheet_id)) with check (ms_private.can_edit_items(sheet_id));
create policy items_delete on myschool.result_items for delete to authenticated
  using (ms_private.can_edit_items(sheet_id));

create policy scans_select on myschool.script_scans for select to authenticated
  using (uploaded_by = (select auth.uid()) or ms_private.is_school_admin(school_id));
create policy scans_insert on myschool.script_scans for insert to authenticated
  with check (uploaded_by = (select auth.uid()) and ms_private.is_staff(school_id));
create policy scans_update on myschool.script_scans for update to authenticated
  using (uploaded_by = (select auth.uid()) or ms_private.is_school_admin(school_id))
  with check (uploaded_by = (select auth.uid()) or ms_private.is_school_admin(school_id));

-- ---------------------------------------------------------------- announcements & audit
create policy announcements_select on myschool.announcements for select to authenticated
  using (ms_private.is_school_admin(school_id)
         or (status = 'published' and (expires_at is null or expires_at > now())
             and ms_private.announcement_visible(school_id, audience)));
create policy announcements_insert on myschool.announcements for insert to authenticated
  with check (ms_private.is_school_admin(school_id));
create policy announcements_update on myschool.announcements for update to authenticated
  using (ms_private.is_school_admin(school_id)) with check (ms_private.is_school_admin(school_id));
create policy announcements_delete on myschool.announcements for delete to authenticated
  using (ms_private.is_school_admin(school_id));

create policy audit_select on myschool.audit_logs for select to authenticated
  using (ms_private.is_school_admin(school_id) or ms_private.is_platform_admin());
