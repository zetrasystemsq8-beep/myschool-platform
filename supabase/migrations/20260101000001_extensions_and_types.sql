-- 01: schemas + enum types.
-- MySchool lives in its OWN schemas so it can share a Supabase project with other apps:
--   myschool     tables, views and RPCs (exposed through the API)
--   ms_private   RLS helper/trigger functions (never exposed)
-- Nothing in `public` and nothing on auth.users is created or modified.
create schema if not exists myschool;
create schema if not exists ms_private;
grant usage on schema myschool   to anon, authenticated, service_role;
grant usage on schema ms_private to anon, authenticated, service_role;

-- platform_admin is a global flag on profiles, deliberately not a school role.
create type myschool.school_role as enum ('student', 'parent', 'teacher', 'school_admin');
create type myschool.member_status as enum ('active', 'suspended');
create type myschool.student_status as enum ('active', 'graduated', 'withdrawn', 'suspended');
create type myschool.enrollment_status as enum ('active', 'promoted', 'repeated', 'withdrawn');
create type myschool.result_status as enum ('draft', 'submitted', 'approved', 'published');
create type myschool.result_source as enum ('manual', 'ocr');
create type myschool.scan_status as enum ('uploaded', 'processing', 'extracted', 'reviewed', 'rejected', 'failed');
create type myschool.announcement_status as enum ('draft', 'published', 'archived');
create type myschool.announcement_audience as enum ('all', 'students', 'parents', 'staff');

create or replace function ms_private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
