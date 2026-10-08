-- =====================================================================================
-- LOCAL DEVELOPMENT / TEST FIXTURES ONLY.  NEVER run this against a production database.
-- Two demo schools (DEMO-A, DEMO-B). All demo passwords: Password123!
-- Student login convention: school DEMO-A + admission ADM001 + PIN "Password123!" (dev only).
-- IDs are fixed so supabase/tests/database/*.sql can reference them.
--   schools   aaaaaaaa-0000-0000-0000-000000000001 (A)   bbbbbbbb-0000-0000-0000-000000000001 (B)
--   users     platform cccccccc-0000-0000-0000-000000000001
--             admin  *-1000-*-1   teacher *-2000-*-1   students *-3000-*-1/2   parent aaaaaaaa-4000-*-1
--   students  *-5000-*-1/2 ; session *-6000 ; term *-6100 ; class *-7000 ; subjects *-7100-*-1/2
--   sheets    aaaaaaaa-9000-*-1 (Maths, published)  -2 (English, draft)   bbbbbbbb-9000-*-1 (published)
-- =====================================================================================

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                        confirmation_token, recovery_token, email_change, email_change_token_new)
select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
       extensions.crypt('Password123!', extensions.gen_salt('bf')), now(),
       '{"provider":"email","providers":["email"]}'::jsonb, jsonb_build_object('full_name', u.name),
       now(), now(), '', '', '', ''
from (values
  ('cccccccc-0000-0000-0000-000000000001'::uuid, 'platform@myschool.test',                'Platform Admin'),
  ('aaaaaaaa-1000-0000-0000-000000000001'::uuid, 'admin.a@myschool.test',                 'Alpha Admin'),
  ('aaaaaaaa-2000-0000-0000-000000000001'::uuid, 'teacher.a@myschool.test',               'Alpha Teacher'),
  ('aaaaaaaa-3000-0000-0000-000000000001'::uuid, 'adm001.demo-a@students.myschool.local', 'Ada Student'),
  ('aaaaaaaa-3000-0000-0000-000000000002'::uuid, 'adm002.demo-a@students.myschool.local', 'Bayo Student'),
  ('aaaaaaaa-4000-0000-0000-000000000001'::uuid, 'parent.a@myschool.test',                'Alpha Parent'),
  ('bbbbbbbb-1000-0000-0000-000000000001'::uuid, 'admin.b@myschool.test',                 'Beta Admin'),
  ('bbbbbbbb-2000-0000-0000-000000000001'::uuid, 'teacher.b@myschool.test',               'Beta Teacher'),
  ('bbbbbbbb-3000-0000-0000-000000000001'::uuid, 'adm001.demo-b@students.myschool.local', 'Chika Student')
) as u(id, email, name);

insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
select gen_random_uuid(), id, jsonb_build_object('sub', id::text, 'email', email), 'email', id::text, now(), now(), now()
from auth.users;

update public.profiles set is_platform_admin = true where id = 'cccccccc-0000-0000-0000-000000000001';

insert into public.schools (id, school_code, name, motto, description, city, state) values
 ('aaaaaaaa-0000-0000-0000-000000000001', 'DEMO-A', 'Demo School Alpha', 'Knowledge first', 'Demo tenant A', 'Ado-Ekiti', 'Ekiti'),
 ('bbbbbbbb-0000-0000-0000-000000000001', 'DEMO-B', 'Demo School Beta',  'Work and learn',  'Demo tenant B', 'Akure', 'Ondo');

insert into public.school_settings (school_id) select id from public.schools;
insert into public.grading_scales (school_id, grade, min_score, remark)
select s.id, g.grade, g.min_score, g.remark from public.schools s,
 (values ('A',70,'Excellent'),('B',60,'Very Good'),('C',50,'Good'),('D',45,'Fair'),('E',40,'Pass'),('F',0,'Fail')) as g(grade, min_score, remark);

insert into public.school_members (school_id, user_id, role, staff_number) values
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-1000-0000-0000-000000000001', 'school_admin', 'A-ADM-1'),
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-2000-0000-0000-000000000001', 'teacher', 'A-T-1'),
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000001', 'student', null),
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000002', 'student', null),
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-4000-0000-0000-000000000001', 'parent', null),
 ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-1000-0000-0000-000000000001', 'school_admin', 'B-ADM-1'),
 ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-2000-0000-0000-000000000001', 'teacher', 'B-T-1'),
 ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001', 'student', null);

insert into public.students (id, school_id, user_id, admission_number, first_name, last_name) values
 ('aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000001', 'ADM001', 'Ada', 'Student'),
 ('aaaaaaaa-5000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-3000-0000-0000-000000000002', 'ADM002', 'Bayo', 'Student'),
 ('bbbbbbbb-5000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-3000-0000-0000-000000000001', 'ADM001', 'Chika', 'Student');

insert into public.student_private (student_id, school_id, date_of_birth, gender) values
 ('aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '2012-05-04', 'female');

insert into public.parent_students (school_id, parent_user_id, student_id, relationship) values
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-4000-0000-0000-000000000001', 'aaaaaaaa-5000-0000-0000-000000000001', 'mother');

insert into public.academic_sessions (id, school_id, name, start_date, end_date, is_current) values
 ('aaaaaaaa-6000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', '2025/2026', '2025-09-08', '2026-07-24', true),
 ('bbbbbbbb-6000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', '2025/2026', '2025-09-08', '2026-07-24', true);
insert into public.terms (id, school_id, session_id, term_number, name, is_current) values
 ('aaaaaaaa-6100-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000001', 1, 'First Term', true),
 ('bbbbbbbb-6100-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-6000-0000-0000-000000000001', 1, 'First Term', true);
insert into public.classes (id, school_id, name, level) values
 ('aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'JSS 1 A', 'JSS 1'),
 ('bbbbbbbb-7000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'JSS 1 A', 'JSS 1');
insert into public.subjects (id, school_id, name, code) values
 ('aaaaaaaa-7100-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Mathematics', 'MTH'),
 ('aaaaaaaa-7100-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'English Language', 'ENG'),
 ('bbbbbbbb-7100-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'Mathematics', 'MTH');

insert into public.teaching_assignments (school_id, teacher_user_id, class_id, subject_id, session_id) values
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-2000-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-7100-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000001'),
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-2000-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-7100-0000-0000-000000000002', 'aaaaaaaa-6000-0000-0000-000000000001'),
 ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-2000-0000-0000-000000000001', 'bbbbbbbb-7000-0000-0000-000000000001', 'bbbbbbbb-7100-0000-0000-000000000001', 'bbbbbbbb-6000-0000-0000-000000000001');

insert into public.enrollments (school_id, student_id, class_id, session_id) values
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-5000-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000001'),
 ('aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-5000-0000-0000-000000000002', 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-6000-0000-0000-000000000001'),
 ('bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-5000-0000-0000-000000000001', 'bbbbbbbb-7000-0000-0000-000000000001', 'bbbbbbbb-6000-0000-0000-000000000001');

-- Sheets: A-Maths already published, A-English still draft, B-Maths published
insert into public.result_sheets (id, school_id, term_id, class_id, subject_id, status, published_at) values
 ('aaaaaaaa-9000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-6100-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-7100-0000-0000-000000000001', 'published', now()),
 ('aaaaaaaa-9000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-6100-0000-0000-000000000001', 'aaaaaaaa-7000-0000-0000-000000000001', 'aaaaaaaa-7100-0000-0000-000000000002', 'draft', null),
 ('bbbbbbbb-9000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-6100-0000-0000-000000000001', 'bbbbbbbb-7000-0000-0000-000000000001', 'bbbbbbbb-7100-0000-0000-000000000001', 'published', now());

insert into public.result_items (id, school_id, sheet_id, student_id, ca_score, exam_score) values
 ('aaaaaaaa-9100-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-9000-0000-0000-000000000001', 'aaaaaaaa-5000-0000-0000-000000000001', 30, 45),
 ('aaaaaaaa-9100-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-9000-0000-0000-000000000001', 'aaaaaaaa-5000-0000-0000-000000000002', 20, 25),
 ('aaaaaaaa-9100-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-9000-0000-0000-000000000002', 'aaaaaaaa-5000-0000-0000-000000000001', 28, 40),
 ('aaaaaaaa-9100-0000-0000-000000000004', 'aaaaaaaa-0000-0000-0000-000000000001', 'aaaaaaaa-9000-0000-0000-000000000002', 'aaaaaaaa-5000-0000-0000-000000000002', 15, 30),
 ('bbbbbbbb-9100-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'bbbbbbbb-9000-0000-0000-000000000001', 'bbbbbbbb-5000-0000-0000-000000000001', 35, 50);

insert into public.announcements (id, school_id, title, body, audience, status) values
 ('aaaaaaaa-a000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Welcome back', 'Term begins Monday.', 'all', 'published'),
 ('aaaaaaaa-a000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 'Draft notice', 'Not ready.', 'all', 'draft'),
 ('aaaaaaaa-a000-0000-0000-000000000003', 'aaaaaaaa-0000-0000-0000-000000000001', 'Staff meeting', 'Friday 2pm.', 'staff', 'published'),
 ('bbbbbbbb-a000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'Beta notice', 'Beta only.', 'all', 'published');
