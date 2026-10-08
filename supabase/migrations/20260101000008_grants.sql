-- 08: table privileges (defence in depth beneath RLS). anon gets NOTHING on tables;
-- anonymous access is limited to the two public discovery functions.

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;

grant select on public.schools, public.school_settings, public.grading_scales, public.profiles,
  public.school_members, public.academic_sessions, public.terms, public.classes, public.subjects,
  public.students, public.student_private, public.parent_students, public.teaching_assignments,
  public.enrollments, public.result_sheets, public.result_items, public.script_scans,
  public.announcements, public.audit_logs, public.published_results to authenticated;

-- column-level writes: school_code / is_active / is_listed, is_platform_admin, role, school_id
-- can never be changed by a client
grant update (name, motto, description, logo_path, website, contact_email, contact_phone, address, city, state)
  on public.schools to authenticated;
grant update (ca_max, exam_max, require_separate_approver, timezone) on public.school_settings to authenticated;
grant update (full_name, phone, avatar_path) on public.profiles to authenticated;
grant update (status, staff_number, job_title) on public.school_members to authenticated;

grant insert, update, delete on public.grading_scales, public.academic_sessions, public.terms,
  public.classes, public.subjects, public.students, public.student_private, public.enrollments,
  public.announcements to authenticated;
grant insert, delete on public.parent_students, public.teaching_assignments to authenticated;
grant insert, delete on public.result_sheets to authenticated;
grant insert, update, delete on public.result_items to authenticated;
grant insert on public.script_scans to authenticated;
grant update (sheet_id, student_id, status, extracted, reviewed_by, reviewed_at) on public.script_scans to authenticated;
-- audit_logs: SELECT only. result_sheets: no UPDATE at all.
