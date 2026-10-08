-- 01: extensions, private helper schema, enum types
create extension if not exists pg_trgm with schema extensions;
create extension if not exists pgcrypto with schema extensions;

-- Helper schema. NOT exposed through the REST API (see config.toml [api].schemas).
create schema if not exists app;
grant usage on schema app to anon, authenticated, service_role;

-- Roles a person can hold INSIDE a school. platform_admin is a global flag on profiles,
-- deliberately not a school role (it belongs to no tenant).
create type public.school_role as enum ('student', 'parent', 'teacher', 'school_admin');
create type public.member_status as enum ('active', 'suspended');
create type public.student_status as enum ('active', 'graduated', 'withdrawn', 'suspended');
create type public.enrollment_status as enum ('active', 'promoted', 'repeated', 'withdrawn');
create type public.result_status as enum ('draft', 'submitted', 'approved', 'published');
create type public.result_source as enum ('manual', 'ocr');
create type public.scan_status as enum ('uploaded', 'processing', 'extracted', 'reviewed', 'rejected', 'failed');
create type public.announcement_status as enum ('draft', 'published', 'archived');
create type public.announcement_audience as enum ('all', 'students', 'parents', 'staff');

create or replace function app.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
