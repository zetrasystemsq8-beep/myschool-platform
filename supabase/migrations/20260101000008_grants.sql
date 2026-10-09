-- 08: table privileges (defence in depth beneath RLS), scoped to the myschool schema ONLY.
-- anon gets NO table access; anonymous use is limited to the two public discovery functions.
revoke all on all tables    in schema myschool from anon, authenticated;
revoke all on all sequences in schema myschool from anon, authenticated;
alter default privileges for role postgres in schema myschool revoke all on tables    from anon, authenticated;
alter default privileges for role postgres in schema myschool revoke all on sequences from anon, authenticated;
grant all on all tables    in schema myschool to service_role;
grant all on all sequences in schema myschool to service_role;
alter default privileges for role postgres in schema myschool grant all on tables    to service_role;
alter default privileges for role postgres in schema myschool grant all on sequences to service_role;

grant select on myschool.schools, myschool.school_settings, myschool.grading_scales, myschool.profiles,
  myschool.school_members, myschool.academic_sessions, myschool.terms, myschool.classes, myschool.subjects,
  myschool.students, myschool.student_private, myschool.parent_students, myschool.teaching_assignments,
  myschool.enrollments, myschool.result_sheets, myschool.result_items, myschool.script_scans,
  myschool.announcements, myschool.audit_logs, myschool.published_results to authenticated;

-- column-level writes: school_code / is_active / is_listed, is_platform_admin, role, school_id
-- can never be changed by a client
grant update (name, motto, description, logo_path, website, contact_email, contact_phone, address, city, state)
  on myschool.schools to authenticated;
grant update (ca_max, exam_max, require_separate_approver, timezone) on myschool.school_settings to authenticated;
grant update (full_name, phone, avatar_path) on myschool.profiles to authenticated;
grant update (status, staff_number, job_title) on myschool.school_members to authenticated;

grant insert, update, delete on myschool.grading_scales, myschool.academic_sessions, myschool.terms,
  myschool.classes, myschool.subjects, myschool.students, myschool.student_private, myschool.enrollments,
  myschool.announcements to authenticated;
grant insert, delete on myschool.parent_students, myschool.teaching_assignments to authenticated;
grant insert, delete on myschool.result_sheets to authenticated;
grant insert, update, delete on myschool.result_items to authenticated;
grant insert on myschool.script_scans to authenticated;
grant update (sheet_id, student_id, status, extracted, reviewed_by, reviewed_at) on myschool.script_scans to authenticated;
-- audit_logs: SELECT only. result_sheets: no UPDATE at all.

notify pgrst, 'reload schema';
