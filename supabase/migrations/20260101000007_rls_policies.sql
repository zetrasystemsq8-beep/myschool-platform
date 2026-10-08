-- 07: Row Level Security. Default = deny. Every policy below is the ONLY way a row becomes visible.
-- Tenant isolation: every policy is anchored on school_id through app.* helpers that check an
-- ACTIVE membership of auth.uid() in that exact school.

alter table public.schools              enable row level security;
alter table public.school_settings      enable row level security;
alter table public.grading_scales       enable row level security;
alter table public.profiles             enable row level security;
alter table public.school_members       enable row level security;
alter table public.academic_sessions    enable row level security;
alter table public.terms                enable row level security;
alter table public.classes              enable row level security;
alter table public.subjects             enable row level security;
alter table public.students             enable row level security;
alter table public.student_private      enable row level security;
alter table public.parent_students      enable row level security;
alter table public.teaching_assignments enable row level security;
alter table public.enrollments          enable row level security;
alter table public.result_sheets        enable row level security;
alter table public.result_items         enable row level security;
alter table public.script_scans         enable row level security;
alter table public.announcements        enable row level security;
alter table public.audit_logs           enable row level security;

-- ---------------------------------------------------------------- schools & settings
create policy schools_select on public.schools for select to authenticated
  using (app.is_member(id) or app.is_platform_admin());
create policy schools_update on public.schools for update to authenticated
  using (app.is_school_admin(id)) with check (app.is_school_admin(id));  -- columns limited by GRANT

create policy settings_select on public.school_settings for select to authenticated
  using (app.is_member(school_id) or app.is_platform_admin());
create policy settings_update on public.school_settings for update to authenticated
  using (app.is_school_admin(school_id)) with check (app.is_school_admin(school_id));

create policy grading_select on public.grading_scales for select to authenticated
  using (app.is_member(school_id));
create policy grading_insert on public.grading_scales for insert to authenticated
  with check (app.is_school_admin(school_id));
create policy grading_update on public.grading_scales for update to authenticated
  using (app.is_school_admin(school_id)) with check (app.is_school_admin(school_id));
create policy grading_delete on public.grading_scales for delete to authenticated
  using (app.is_school_admin(school_id));

-- ---------------------------------------------------------------- identity & membership
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or app.admin_of_profile(id) or app.is_platform_admin());
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid())); -- is_platform_admin not grantable

create policy members_select on public.school_members for select to authenticated
  using (user_id = (select auth.uid()) or app.is_school_admin(school_id) or app.is_platform_admin());
create policy members_update on public.school_members for update to authenticated
  using (app.is_school_admin(school_id)) with check (app.is_school_admin(school_id));
-- INSERT/DELETE on school_members: server side only (Edge Function with service role).

-- ---------------------------------------------------------------- academic structure
do $$
declare t text;
begin
  foreach t in array array['academic_sessions', 'terms', 'classes', 'subjects'] loop
    execute format('create policy %1$s_select on public.%1$I for select to authenticated using (app.is_member(school_id))', t);
    execute format('create policy %1$s_insert on public.%1$I for insert to authenticated with check (app.is_school_admin(school_id))', t);
    execute format('create policy %1$s_update on public.%1$I for update to authenticated using (app.is_school_admin(school_id)) with check (app.is_school_admin(school_id))', t);
    execute format('create policy %1$s_delete on public.%1$I for delete to authenticated using (app.is_school_admin(school_id))', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- people
create policy students_select on public.students for select to authenticated
  using (app.is_school_admin(school_id) or app.is_self_or_parent_of(id) or app.teaches_student(id));
create policy students_insert on public.students for insert to authenticated
  with check (app.is_school_admin(school_id));
create policy students_update on public.students for update to authenticated
  using (app.is_school_admin(school_id)) with check (app.is_school_admin(school_id));
create policy students_delete on public.students for delete to authenticated
  using (app.is_school_admin(school_id));

-- teachers are deliberately NOT able to read this table
create policy student_private_select on public.student_private for select to authenticated
  using (app.is_school_admin(school_id) or app.is_self_or_parent_of(student_id));
create policy student_private_insert on public.student_private for insert to authenticated
  with check (app.is_school_admin(school_id));
create policy student_private_update on public.student_private for update to authenticated
  using (app.is_school_admin(school_id)) with check (app.is_school_admin(school_id));
create policy student_private_delete on public.student_private for delete to authenticated
  using (app.is_school_admin(school_id));

create policy parent_students_select on public.parent_students for select to authenticated
  using (parent_user_id = (select auth.uid()) or app.is_school_admin(school_id));
create policy parent_students_insert on public.parent_students for insert to authenticated
  with check (app.is_school_admin(school_id));
create policy parent_students_delete on public.parent_students for delete to authenticated
  using (app.is_school_admin(school_id));

create policy assignments_select on public.teaching_assignments for select to authenticated
  using (app.is_school_admin(school_id) or teacher_user_id = (select auth.uid()));
create policy assignments_insert on public.teaching_assignments for insert to authenticated
  with check (app.is_school_admin(school_id));
create policy assignments_delete on public.teaching_assignments for delete to authenticated
  using (app.is_school_admin(school_id));

create policy enrollments_select on public.enrollments for select to authenticated
  using (app.is_school_admin(school_id) or app.is_self_or_parent_of(student_id)
         or app.teacher_assigned_class(school_id, class_id, session_id));
create policy enrollments_insert on public.enrollments for insert to authenticated
  with check (app.is_school_admin(school_id));
create policy enrollments_update on public.enrollments for update to authenticated
  using (app.is_school_admin(school_id)) with check (app.is_school_admin(school_id));
create policy enrollments_delete on public.enrollments for delete to authenticated
  using (app.is_school_admin(school_id));

-- ---------------------------------------------------------------- results
-- Sheets: admin + assigned teacher always; students/parents ONLY when published.
create policy sheets_select on public.result_sheets for select to authenticated
  using (app.can_work_sheet_keys(school_id, term_id, class_id, subject_id)
         or (status = 'published' and app.has_role(school_id, array['student','parent']::public.school_role[])));
create policy sheets_insert on public.result_sheets for insert to authenticated
  with check (status = 'draft' and created_by = (select auth.uid())
              and app.can_work_sheet_keys(school_id, term_id, class_id, subject_id));
create policy sheets_delete on public.result_sheets for delete to authenticated
  using (status = 'draft' and app.is_school_admin(school_id));
-- No UPDATE policy: status moves only through the workflow RPCs (security definer).

create policy items_select on public.result_items for select to authenticated
  using (app.can_work_sheet(sheet_id)
         or (app.sheet_is_published(sheet_id) and app.is_self_or_parent_of(student_id)));
create policy items_insert on public.result_items for insert to authenticated
  with check (app.can_edit_items(sheet_id));
create policy items_update on public.result_items for update to authenticated
  using (app.can_edit_items(sheet_id)) with check (app.can_edit_items(sheet_id));
create policy items_delete on public.result_items for delete to authenticated
  using (app.can_edit_items(sheet_id));

create policy scans_select on public.script_scans for select to authenticated
  using (uploaded_by = (select auth.uid()) or app.is_school_admin(school_id));
create policy scans_insert on public.script_scans for insert to authenticated
  with check (uploaded_by = (select auth.uid()) and app.is_staff(school_id));
create policy scans_update on public.script_scans for update to authenticated
  using (uploaded_by = (select auth.uid()) or app.is_school_admin(school_id))
  with check (uploaded_by = (select auth.uid()) or app.is_school_admin(school_id));

-- ---------------------------------------------------------------- announcements & audit
create policy announcements_select on public.announcements for select to authenticated
  using (app.is_school_admin(school_id)
         or (status = 'published' and (expires_at is null or expires_at > now())
             and app.announcement_visible(school_id, audience)));
create policy announcements_insert on public.announcements for insert to authenticated
  with check (app.is_school_admin(school_id));
create policy announcements_update on public.announcements for update to authenticated
  using (app.is_school_admin(school_id)) with check (app.is_school_admin(school_id));
create policy announcements_delete on public.announcements for delete to authenticated
  using (app.is_school_admin(school_id));

create policy audit_select on public.audit_logs for select to authenticated
  using (app.is_school_admin(school_id) or app.is_platform_admin());
