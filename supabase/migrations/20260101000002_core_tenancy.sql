-- 02: tenants (schools), per-school settings, grading scale, identity (profiles), membership

create table public.schools (
  id           uuid primary key default gen_random_uuid(),
  school_code  text not null,                       -- the public "School ID", e.g. 'CHR-ADO'
  name         text not null check (char_length(name) between 2 and 150),
  motto        text check (char_length(motto) <= 200),
  description  text check (char_length(description) <= 2000),
  logo_path    text,                                -- path inside the public 'school-logos' bucket
  website      text,
  contact_email text,
  contact_phone text,
  address      text,
  city         text,
  state        text,
  country      text not null default 'NG',
  is_active    boolean not null default true,       -- inactive = nobody can use the school
  is_listed    boolean not null default true,       -- listed in public search
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint schools_code_format check (school_code ~ '^[A-Z0-9][A-Z0-9-]{2,19}$')
);
create unique index schools_code_key on public.schools (school_code);
create index schools_name_trgm on public.schools using gin (name extensions.gin_trgm_ops);

create table public.school_settings (
  school_id   uuid primary key references public.schools (id) on delete cascade,
  ca_max      numeric(5,2) not null default 40 check (ca_max >= 0),
  exam_max    numeric(5,2) not null default 60 check (exam_max >= 0),
  require_separate_approver boolean not null default false, -- approver must differ from submitter
  timezone    text not null default 'Africa/Lagos',
  updated_at  timestamptz not null default now(),
  constraint settings_total_100 check (ca_max + exam_max = 100)
);

-- Grade = row with the highest min_score <= total. A scale must contain min_score 0.
create table public.grading_scales (
  school_id  uuid not null references public.schools (id) on delete cascade,
  grade      text not null check (char_length(grade) between 1 and 3),
  min_score  numeric(5,2) not null check (min_score between 0 and 100),
  remark     text,
  primary key (school_id, grade),
  unique (school_id, min_score)
);

-- One row per auth user: global identity only. Nothing school-specific lives here.
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text,
  phone       text,
  avatar_path text,
  is_platform_admin boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- A user's role in a school. A person may belong to several schools (e.g. a parent).
create table public.school_members (
  id           uuid primary key default gen_random_uuid(),
  school_id    uuid not null references public.schools (id) on delete cascade,
  user_id      uuid not null references public.profiles (id) on delete cascade,
  role         public.school_role not null,
  status       public.member_status not null default 'active',
  staff_number text,
  job_title    text,
  created_at   timestamptz not null default now(),
  unique (school_id, user_id),            -- one role per person per school
  unique (school_id, staff_number)
);
create index school_members_user_idx on public.school_members (user_id) where status = 'active';
