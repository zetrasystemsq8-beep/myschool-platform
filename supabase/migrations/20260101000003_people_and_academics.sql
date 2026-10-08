-- 03: students, parents, academic structure. Every tenant table carries school_id and has
-- UNIQUE (id, school_id) so children can use COMPOSITE foreign keys. That makes cross-school
-- references impossible at the database level, regardless of RLS.

create table public.academic_sessions (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null references public.schools (id) on delete cascade,
  name       text not null,                       -- '2025/2026'
  start_date date not null,
  end_date   date not null,
  is_current boolean not null default false,
  created_at timestamptz not null default now(),
  unique (school_id, name),
  unique (id, school_id),
  check (end_date > start_date)
);
create unique index one_current_session on public.academic_sessions (school_id) where is_current;

create table public.terms (
  id          uuid primary key default gen_random_uuid(),
  school_id   uuid not null,
  session_id  uuid not null,
  term_number smallint not null check (term_number between 1 and 4),
  name        text not null,                      -- 'First Term'
  start_date  date,
  end_date    date,
  is_current  boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (session_id, term_number),
  unique (id, school_id),
  foreign key (session_id, school_id) references public.academic_sessions (id, school_id) on delete cascade,
  check (end_date is null or start_date is null or end_date > start_date)
);
create unique index one_current_term on public.terms (school_id) where is_current;

create table public.classes (
  id        uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id) on delete cascade,
  name      text not null,                        -- 'JSS 1 A'
  level     text,                                 -- 'JSS 1' (grouping/promotion)
  created_at timestamptz not null default now(),
  unique (school_id, name),
  unique (id, school_id)
);

create table public.subjects (
  id        uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id) on delete cascade,
  name      text not null,
  code      text not null,
  created_at timestamptz not null default now(),
  unique (school_id, code),
  unique (id, school_id)
);

-- Student record (minimal, non-sensitive). user_id is null until a login account exists.
create table public.students (
  id               uuid primary key default gen_random_uuid(),
  school_id        uuid not null references public.schools (id) on delete cascade,
  user_id          uuid unique,
  admission_number text not null check (char_length(admission_number) between 1 and 40),
  first_name       text not null,
  last_name        text not null,
  other_names      text,
  photo_path       text,
  status           public.student_status not null default 'active',
  admitted_on      date,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (school_id, admission_number),
  unique (id, school_id),
  foreign key (school_id, user_id) references public.school_members (school_id, user_id) on delete restrict
);

-- Sensitive personal data, kept apart so teachers cannot read it (only admin / the student / parents).
create table public.student_private (
  student_id    uuid primary key,
  school_id     uuid not null,
  date_of_birth date,
  gender        text check (gender in ('female', 'male')),
  home_address  text,
  updated_at    timestamptz not null default now(),
  foreign key (student_id, school_id) references public.students (id, school_id) on delete cascade
);

create table public.parent_students (
  school_id      uuid not null,
  parent_user_id uuid not null,
  student_id     uuid not null,
  relationship   text,
  created_at     timestamptz not null default now(),
  primary key (parent_user_id, student_id),
  foreign key (school_id, parent_user_id) references public.school_members (school_id, user_id) on delete cascade,
  foreign key (student_id, school_id) references public.students (id, school_id) on delete cascade
);
create index parent_students_student_idx on public.parent_students (student_id);

-- Which teacher teaches which subject to which class in which session.
create table public.teaching_assignments (
  id              uuid primary key default gen_random_uuid(),
  school_id       uuid not null,
  teacher_user_id uuid not null,
  class_id        uuid not null,
  subject_id      uuid not null,
  session_id      uuid not null,
  created_at      timestamptz not null default now(),
  unique (teacher_user_id, class_id, subject_id, session_id),
  foreign key (school_id, teacher_user_id) references public.school_members (school_id, user_id) on delete cascade,
  foreign key (class_id, school_id) references public.classes (id, school_id) on delete cascade,
  foreign key (subject_id, school_id) references public.subjects (id, school_id) on delete cascade,
  foreign key (session_id, school_id) references public.academic_sessions (id, school_id) on delete cascade
);
create index teaching_assignments_class_idx on public.teaching_assignments (class_id, session_id);

-- A student sits in exactly one class per session.
create table public.enrollments (
  id         uuid primary key default gen_random_uuid(),
  school_id  uuid not null,
  student_id uuid not null,
  class_id   uuid not null,
  session_id uuid not null,
  status     public.enrollment_status not null default 'active',
  created_at timestamptz not null default now(),
  unique (student_id, session_id),
  unique (id, school_id),
  foreign key (student_id, school_id) references public.students (id, school_id) on delete restrict,
  foreign key (class_id, school_id) references public.classes (id, school_id) on delete restrict,
  foreign key (session_id, school_id) references public.academic_sessions (id, school_id) on delete restrict
);
create index enrollments_class_idx on public.enrollments (class_id, session_id);
